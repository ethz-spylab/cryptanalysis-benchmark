#!/usr/bin/env python3
"""Patch crypton1.c (the upstream v1.0 cipher source) for a reduced-rounds variant.

Usage: patch_crypton.py <target_file> <R>

  <target_file>  path to the upstream cipher source (crypton1.c) to edit in place
  <R>            total round count (= R-1 unrolled f-rnd calls + final
                 gamma_tau-round). Upstream is R=12.

The CR/CRLF line endings of the Windows-era reference source are normalised
away before the regex edits run (build_cli.sh strips them too), so the patch
behaves identically whether handed the raw archive file or a pre-normalised
copy.
"""
import re
import sys

PATH = sys.argv[1]
R = int(sys.argv[2])
assert 2 <= R <= 12

with open(PATH) as f:
    src = f.read()
# Normalise Windows line endings so the body/whitening regexes match.
src = src.replace("\r", "")


def build_encrypt_body(R: int) -> str:
    n_calls = R - 1
    parity_swap = (n_calls % 2 == 0)  # last call f1 -> state in b0 -> need swap
    lines = []
    lines.append("    u4byte  b0[4], b1[4];")
    lines.append("")
    lines.append("    b0[0] = in_blk[0] ^ e_key[0]; b0[1] = in_blk[1] ^ e_key[1];")
    lines.append("    b0[2] = in_blk[2] ^ e_key[2]; b0[3] = in_blk[3] ^ e_key[3];")
    lines.append("")
    for k in range(1, n_calls + 1):
        macro = "f0_rnd" if (k % 2 == 1) else "f1_rnd"
        lines.append(f"    {macro}(e_key + {4*k:>2});")
    if parity_swap:
        lines.append("    b1[0] = b0[0]; b1[1] = b0[1]; b1[2] = b0[2]; b1[3] = b0[3];")
    lines.append("")
    lines.append("    gamma_tau(0); gamma_tau(1); gamma_tau(2); gamma_tau(3);")
    lines.append("")
    lines.append(f"    out_blk[0] = b0[0] ^ e_key[{4*R}]; out_blk[1] = b0[1] ^ e_key[{4*R+1}];")
    lines.append(f"    out_blk[2] = b0[2] ^ e_key[{4*R+2}]; out_blk[3] = b0[3] ^ e_key[{4*R+3}];")
    return "\n".join(lines)


def build_decrypt_body(R: int) -> str:
    """Decrypt keeps the LAST R-1 f-rnd calls of upstream's 11-call list.

    Upstream call k (1..11) is f0_rnd(d_key+4k) for k odd, f1_rnd for k even.
    We keep calls (13-R)..11. The first kept call's f-type determines whether
    decrypt's pre-W places state in b0 (f0 starts) or b1 (f1 starts).
    """
    n_calls = R - 1
    first_call_idx = 13 - R           # 1-based index into upstream's call list
    first_is_f0 = (first_call_idx % 2 == 1)
    last_call_idx = 11
    # last call f-type
    last_is_f0 = (last_call_idx % 2 == 1)  # always True (11 odd) — kept for clarity

    pre_buf = "b0" if first_is_f0 else "b1"
    other = "b1" if first_is_f0 else "b0"

    lines = []
    lines.append("    u4byte  b0[4], b1[4];")
    lines.append("")
    lines.append(f"    {pre_buf}[0] = in_blk[0] ^ d_key[0]; {pre_buf}[1] = in_blk[1] ^ d_key[1];")
    lines.append(f"    {pre_buf}[2] = in_blk[2] ^ d_key[2]; {pre_buf}[3] = in_blk[3] ^ d_key[3];")
    # Suppress -Wmaybe-uninitialized: the first f-rnd writes the OTHER buffer
    # in full before anything reads it.
    lines.append(f"    (void){other};")
    lines.append("")
    for k in range(first_call_idx, last_call_idx + 1):
        macro = "f0_rnd" if (k % 2 == 1) else "f1_rnd"
        lines.append(f"    {macro}(d_key + {4*k:>2});")
    # parity check on number of calls: state must end in b1 for gamma_tau.
    # f-types alternate; with proper pre-W placement, after n_calls
    # alternations starting from `pre_buf`, state ends in (pre_buf if
    # n_calls even else other). We need state in b1.
    # If first_is_f0 (pre_buf=b0): after n_calls alternations, ends in b0
    #   if n_calls even, b1 if odd. Need n_calls odd.
    # If !first_is_f0 (pre_buf=b1): ends in b1 if n_calls even, b0 if odd.
    #   Need n_calls even.
    # The specific R values we care about (8,6,4) all satisfy this without
    # an extra swap — verified by the table:
    #   R=8 -> n_calls=7,  first_is_f0=True (idx=5),  ends in b1 ✓
    #   R=6 -> n_calls=5,  first_is_f0=True (idx=7),  ends in b1 ✓
    #   R=4 -> n_calls=3,  first_is_f0=True (idx=9),  ends in b1 ✓
    if first_is_f0:
        assert n_calls % 2 == 1, f"decrypt parity broken for R={R}"
    else:
        assert n_calls % 2 == 0, f"decrypt parity broken for R={R}"
    lines.append("")
    lines.append("    gamma_tau(0); gamma_tau(1); gamma_tau(2); gamma_tau(3);")
    lines.append("")
    lines.append("    out_blk[0] = b0[0] ^ d_key[48]; out_blk[1] = b0[1] ^ d_key[49];")
    lines.append("    out_blk[2] = b0[2] ^ d_key[50]; out_blk[3] = b0[3] ^ d_key[51];")
    return "\n".join(lines)


def replace_body(src: str, fname: str, new_body: str) -> str:
    pattern = re.compile(
        r"void\s+" + fname + r"\(const u4byte in_blk\[4\], u4byte out_blk\[4?\]\)\s*\{[^}]*\};",
        re.DOTALL,
    )
    # Build replacement: keep original signature literal, swap body.
    m = pattern.search(src)
    if not m:
        raise SystemExit(f"could not find {fname} body")
    sig = m.group(0).split("{", 1)[0]
    return src.replace(m.group(0), sig + "{\n" + new_body + "\n};", 1)


src = replace_body(src, "encrypt", build_encrypt_body(R))
src = replace_body(src, "decrypt", build_decrypt_body(R))

# Replace the e_key post-process indices: row_perm e_key[4R..4R+3] instead
# of e_key[48..51], and override d_key[0..3] = e_key[4R..4R+3] post-row_perm
# so decrypt's pre-W inverts the new encrypt post-W.
post_pat = re.compile(
    r"    e_key\[48\] = row_perm\(rotr\(e_key\[48\],16\)\);\s*\n"
    r"    e_key\[49\] = row_perm\(rotr\(e_key\[49\], 8\)\);\s*\n"
    r"    e_key\[50\] = row_perm\(e_key\[50\]\);\s*\n"
    r"    e_key\[51\] = row_perm\(rotr\(e_key\[51\],24\)\);"
)
post_replace = (
    f"    e_key[{4*R+0}] = row_perm(rotr(e_key[{4*R+0}],16));\n"
    f"    e_key[{4*R+1}] = row_perm(rotr(e_key[{4*R+1}], 8));\n"
    f"    e_key[{4*R+2}] = row_perm(e_key[{4*R+2}]);\n"
    f"    e_key[{4*R+3}] = row_perm(rotr(e_key[{4*R+3}],24));\n"
    f"    d_key[0] = e_key[{4*R+0}];\n"
    f"    d_key[1] = e_key[{4*R+1}];\n"
    f"    d_key[2] = e_key[{4*R+2}];\n"
    f"    d_key[3] = e_key[{4*R+3}];"
)
src, n = post_pat.subn(post_replace, src)
assert n == 1, f"e_key post-process patch did not match (n={n})"

with open(PATH, "w") as f:
    f.write(src)
print(f"patch_crypton: applied for R={R} to {PATH}", file=sys.stderr)
