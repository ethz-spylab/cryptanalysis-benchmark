#!/usr/bin/env python3
"""Scale-down patcher for LEDAkem (NIST PQC, Round-1 submission).

Three coordinated edits in the extracted Reference_Implementation tree. The
first two are restricted to the CATEGORY==1 / N0==2 parameter set the CLI is
compiled with (`-DCATEGORY=1 -DN0=2`); the third is a mask-width bug fix in the
error sampler that must be applied for the reduced sizes to be sound:

1. Reference_Implementation/KEM/include/qc_ldpc_parameters.h
   Reduce the circulant block size P and the intentional error weight
   NUM_ERRORS_T. K, N and DC are derived macros and update automatically;
   DV is held at 17 (kept odd). The shipped CAT1/N0=2 values (P=27779,
   NUM_ERRORS_T=224) are unique in the header, so the targeted line-rewrites
   cannot touch any other parameter block.

2. Reference_Implementation/KEM/include/bf_decoding.h
   Rescale the hardcoded SYNDROME_TRESH_LOOKUP_TABLE in the CAT1/N0=2 block.
   Contrary to the scaling proposal's note, the bit-flipping threshold is NOT
   computed at runtime: the decoder binary-searches this table keyed on the
   syndrome weight, which scales with P/t. The *threshold* column (62..70)
   depends only on DV and M (both unchanged), so it is kept verbatim; only the
   syndrome-weight breakpoints (column 1) are rescaled by P/27779. Without this,
   decapsulation fails for every key at the reduced sizes (the search always
   returns the smallest-weight threshold and the decoder never converges).

3. Reference_Implementation/KEM/library/gf2x_arith_mod_xPplusOne.c
   Fix the error-position sampler mask width. rand_circulant_blocks_sequence()
   draws error positions over the whole code, calling
     rand_range(N0*NUM_BITS_GF2X_ELEMENT, BITS_TO_REPRESENT(P), ...)
   i.e. a range of N0*P but a mask of only ceil(log2 P) bits. The rejection
   loop `while (rnd_value >= n)` can then NEVER fire (the mask maxes out below
   N0*P), so every error position is confined to [0, 2^ceil(log2 P)). For P just
   under a power of two (all reduced bands: 7907<2^13, 10909<2^14, 15859<2^14)
   this leaves the second circulant block only a tiny sliver of possible error
   positions (~2^ceil(log2 P) - P coords), collapsing the intended QC-LDPC
   decoding problem to a sub-second Prange/ISD solve independent of the chosen
   weight. The fix masks on the ACTUAL range: BITS_TO_REPRESENT(P) ->
   BITS_TO_REPRESENT(N0*NUM_BITS_GF2X_ELEMENT), so errors are uniform over the
   whole code as the scheme intends. (The sibling single-block call in
   rand_circulant_sparse_block uses range NUM_BITS_GF2X_ELEMENT and is already
   correctly masked with BITS_TO_REPRESENT(P) -- it is left untouched.)

Usage:
    patch_ledakem.py <extract_root> <P> <NUM_ERRORS_T>

<extract_root> is the directory that directly contains Reference_Implementation/
(i.e. the unzip target). Fails loudly (non-zero exit) if any substitution does
not change exactly what is expected, so a mis-applied patch aborts variant
generation instead of silently shipping an unweakened / undecodable build.
"""
import os
import re
import sys

# Shipped CATEGORY==1 / N0==2 calibration the table was tuned for.
BASE_P = 27779
# (syndrome-weight breakpoint, threshold) rows of the shipped CAT1/N0=2 table.
BASE_TABLE = [
    (0, 62), (4588, 63), (7609, 64), (9152, 65), (10129, 66),
    (10800, 67), (11261, 68), (11614, 69), (11885, 70),
]


def patch_params(path: str, p_val: str, t_val: str) -> None:
    with open(path) as fh:
        text = fh.read()
    text, n_p = re.subn(
        r"(#define\s+P\s+\()27779(\))",
        lambda m: m.group(1) + p_val + m.group(2), text)
    text, n_t = re.subn(
        r"(#define\s+NUM_ERRORS_T\s+\()224(\))",
        lambda m: m.group(1) + t_val + m.group(2), text)
    if n_p != 1:
        sys.exit(f"FATAL: expected 1 P substitution, made {n_p}")
    if n_t != 1:
        sys.exit(f"FATAL: expected 1 NUM_ERRORS_T substitution, made {n_t}")
    with open(path, "w") as fh:
        fh.write(text)
    sys.stderr.write(f"patched P={p_val} NUM_ERRORS_T={t_val} in {path}\n")


def scaled_table(p_val: int):
    r = p_val / BASE_P
    rows = []
    last = -1
    for bp, th in BASE_TABLE:
        s = round(bp * r)
        if s <= last:          # keep strictly increasing for the binary search
            s = last + 1
        last = s
        rows.append((s, th))
    return rows


def patch_threshold(path: str, p_val: int) -> None:
    with open(path) as fh:
        lines = fh.read().split("\n")
    rows = scaled_table(p_val)
    new_rows = [f"#define SYNDROME_TRESH_LOOKUP_TABLE {{{rows[0][0]},{rows[0][1]}}},\\"]
    for s, th in rows[1:-1]:
        new_rows.append(f"{{{s},{th}}},\\")
    new_rows.append(f"{{{rows[-1][0]},{rows[-1][1]}}}")

    out, i, replaced = [], 0, 0
    while i < len(lines):
        if lines[i].strip() == "#if (CATEGORY == 1) && (N0 == 2)":
            out.append(lines[i]); i += 1
            saw_table = False
            while lines[i].strip() != "#endif":
                if "SYNDROME_TRESH_LOOKUP_TABLE" in lines[i]:
                    saw_table = True
                i += 1
            if not saw_table:
                sys.exit("FATAL: CAT1/N0=2 block lacked SYNDROME_TRESH_LOOKUP_TABLE")
            out.extend(new_rows)
            out.append(lines[i]); i += 1   # the #endif
            replaced += 1
        else:
            out.append(lines[i]); i += 1
    if replaced != 1:
        sys.exit(f"FATAL: expected 1 CAT1/N0=2 threshold block, found {replaced}")
    with open(path, "w") as fh:
        fh.write("\n".join(out))
    sys.stderr.write(
        f"rescaled SYNDROME_TRESH_LOOKUP_TABLE (P={p_val}) in {path}\n")


def patch_sampler(path: str) -> None:
    """Widen the rand_range mask in rand_circulant_blocks_sequence so the range
    N0*NUM_BITS_GF2X_ELEMENT is fully covered (was masked for P only)."""
    with open(path) as fh:
        text = fh.read()
    anchor = "rand_range(N0*NUM_BITS_GF2X_ELEMENT,BITS_TO_REPRESENT(P),"
    fixed = "rand_range(N0*NUM_BITS_GF2X_ELEMENT,BITS_TO_REPRESENT(N0*NUM_BITS_GF2X_ELEMENT),"
    n = text.count(anchor)
    if n != 1:
        sys.exit(f"FATAL: expected 1 blocks_sequence rand_range call, found {n} in {path}")
    text = text.replace(anchor, fixed, 1)
    with open(path, "w") as fh:
        fh.write(text)
    sys.stderr.write(f"widened rand_range mask (blocks_sequence) in {path}\n")


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write("usage: patch_ledakem.py <extract_root> <P> <T>\n")
        return 2
    root, p_val, t_val = sys.argv[1], sys.argv[2], sys.argv[3]
    p_int = int(p_val); int(t_val)

    inc = os.path.join(root, "Reference_Implementation", "KEM", "include")
    params_h = os.path.join(inc, "qc_ldpc_parameters.h")
    bf_h = os.path.join(inc, "bf_decoding.h")
    sampler_c = os.path.join(
        root, "Reference_Implementation", "KEM", "library",
        "gf2x_arith_mod_xPplusOne.c")
    for f in (params_h, bf_h, sampler_c):
        if not os.path.isfile(f):
            sys.exit(f"FATAL: expected file not found: {f}")

    patch_params(params_h, p_val, t_val)
    patch_threshold(bf_h, p_int)
    patch_sampler(sampler_c)
    return 0


if __name__ == "__main__":
    sys.exit(main())
