#!/usr/bin/env python3
"""Reduce SWIFFTX's FFT dimension N (and the cascade of coupled constants).

Per `variant_workfolder/final_fixes_recommendation.md` § SWIFFTX, three knobs
are tied together: `#define N`, `#define LOGN` (= log2(N)), and
`SWIFFTX_OUTPUT_BLOCK_SIZE` (= N+1). OMEGA must be a primitive 2N-th root of
unity in Z_257; the upstream OMEGA = 42 has order 128 (= 2*64), so for smaller
N we use `42^(64/N) mod 257`.

The four HAIFA_IV[N+1] tables are sliced from the upstream tables (they serve
as deterministic constant byte sources for a hash function — an attacker
computing the reduced SWIFFTX sees the same constants we do, which is the
property the benchmark needs).

**Coupled-constant rewrite in `ComputeSingleSWIFFT` / `ComputeSingleSWIFFTX`.**
The upstream reference hard-codes several N=64-specific literals. Reducing only
`#define N` leaves the message-absorption path inconsistent and — critically —
makes the compression IGNORE most of every input block, so trivial collisions
(flip an unread byte) exist with zero cryptanalysis. The reduced build must
rewrite ALL of the following in lock-step (each is validated by an exact-match
substitution; the count is asserted):

  1. `in += 8`  -> `in += EIGHTH_N`   input stride = N/8 bytes read per group.
  2. `a  += 64` -> `a  += N`          A-coefficient stride = N per group.
  3. base-256 packing stride `result/output + (8*i)` -> `+ (EIGHTH_N*i)`
     (the loop runs a FIXED 8 chunks of EIGHTH_N elements; the per-chunk
     offset is EIGHTH_N, NOT the literal 8 — the loop BOUND stays 8).
  4. the three first-tier SWIFFTs must absorb the whole input block, i.e.
     `SWIFFTX_INPUT_BLOCK_SIZE / EIGHTH_N` groups (== 2048/N), with the A slab
     offset scaled to `N * (that count)` (== the full 2048-coeff slab).
  5. the second-tier SWIFFT must absorb the whole (3N+8)-byte intermediate:
     `(3*N + 8) / EIGHTH_N` groups (upstream `(3*EIGHTH_N)+1` only equals this
     at N=64).
  6. `As[3*M*N]` -> `As[3*M*64]` keeps the full 6144-entry PI-derived table;
     declaring it `3*M*N` truncates it for N<64 so the full-block absorption in
     (4) would read past the array.

Without (1)+(3)-(6) the reduced hash silently drops input bytes and is
trivially collidable; (3)-(6) also keep it deterministic (partial writes to the
intermediate would otherwise leave uninitialised bytes the 2nd tier reads).

Usage: patch_swifftx.py <N> <LOGN> <OMEGA> <SWIFFTX.c> <SHA3.h> <SHA3.c>
"""

import re
import sys

if len(sys.argv) != 7:
    raise SystemExit(f"usage: {sys.argv[0]} N LOGN OMEGA SWIFFTX.c SHA3.h SHA3.c")

N = int(sys.argv[1])
LOGN = int(sys.argv[2])
OMEGA = int(sys.argv[3])
swifftx_c = sys.argv[4]
sha3_h = sys.argv[5]
sha3_c = sys.argv[6]


def read(p):
    with open(p, "rb") as f:
        return f.read().decode("latin-1")


def write(p, s):
    with open(p, "wb") as f:
        f.write(s.encode("latin-1"))


# ---- SWIFFTX.c ----
src = read(swifftx_c)
patched = 0


def sub_literal(s, old, new_):
    """Exact-match single substitution; hard-fail if the anchor is missing or
    the replacement is a no-op (guards against upstream drift)."""
    global patched
    if s.count(old) < 1:
        raise SystemExit(f"patch_swifftx: anchor not found: {old!r}")
    out = s.replace(old, new_, 1)
    if out == s:
        raise SystemExit(f"patch_swifftx: no-op replacement for: {old!r}")
    patched += 1
    return out


# --- dimension #defines ---
new = re.sub(r"^#define\s+N\s+64\b", f"#define N {N}", src, count=1, flags=re.M)
patched += new != src
src = new
new = re.sub(r"^#define\s+LOGN\s+6\b", f"#define LOGN {LOGN}", src, count=1, flags=re.M)
patched += new != src
src = new
new = re.sub(
    r"^#define\s+OMEGA\s+42\b", f"#define OMEGA {OMEGA}", src, count=1, flags=re.M
)
patched += new != src
src = new

# --- (1)+(2) per-group input and A-coefficient strides ---
# `for (j = 0; j < m; ++j, in += 8, a += 64)`: 8 = N/8 bytes read per group
# (EIGHTH_N), 64 = N A-coefficients per group.
src = sub_literal(src, "in += 8, a += 64)", "in += EIGHTH_N, a += N)")

# --- (3) base-256 packing stride ---
# The loop runs a FIXED 8 chunks (N / EIGHTH_N == 8), each TranslateToBase256
# consuming EIGHTH_N field elements, so the per-chunk offset must be EIGHTH_N.
# The loop BOUND (`i < 8`) stays 8; only the `8 * i` offsets are N-coupled.
src = sub_literal(
    src,
    "TranslateToBase256(result + (8 * i), output + (8 * i))",
    "TranslateToBase256(result + (EIGHTH_N * i), output + (EIGHTH_N * i))",
)

# --- (4) three first-tier SWIFFTs absorb the WHOLE input block ---
# SWIFFTX_INPUT_BLOCK_SIZE bytes / EIGHTH_N bytes-per-group groups, each
# consuming N A-coefficients -> slab offset N * (that count) (the full slab).
count = "(SWIFFTX_INPUT_BLOCK_SIZE / EIGHTH_N)"
src = sub_literal(
    src,
    "ComputeSingleSWIFFT(input, M, intermediate, As);",
    f"ComputeSingleSWIFFT(input, {count}, intermediate, As);",
)
src = sub_literal(
    src,
    "ComputeSingleSWIFFT(input, M, intermediate + N, As + (N * M));",
    f"ComputeSingleSWIFFT(input, {count}, intermediate + N, As + (N * {count}));",
)
src = sub_literal(
    src,
    "ComputeSingleSWIFFT(input, M, intermediate + (2 * N), As + (2 * N * M));",
    f"ComputeSingleSWIFFT(input, {count}, intermediate + (2 * N), "
    f"As + (2 * N * {count}));",
)

# --- (5) second-tier SWIFFT absorbs the whole (3N+8)-byte intermediate ---
# (3*N + 8) / EIGHTH_N groups. Upstream `(3*EIGHTH_N)+1` only equals this at
# N=64.
src = sub_literal(
    src,
    "(3 * EIGHTH_N) + 1 , output, As);",
    "((3 * N + 8) / EIGHTH_N) , output, As);",
)

# --- (6) keep the full 6144-entry As table ---
# `As[3*M*N]` truncates the PI-derived initialiser to 3*M*N < 6144 for N<64,
# so the full-block absorption in (4) would read past the array. 3*M*64 == 6144
# keeps every initialiser (M == SWIFFTX_INPUT_BLOCK_SIZE/8 == 32 is unchanged).
src = sub_literal(
    src, "const int16_t As[3 * M * N] =", "const int16_t As[3 * M * 64] ="
)

if patched != 10:
    raise SystemExit(f"patch_swifftx: SWIFFTX.c unexpected patch count {patched}")

# `TranslateToBase256` works only for EIGHTH_N >= 2 — its base-257-to-base-256
# carry chain accesses input[i+1]/pairs[EIGHTH_N/2 - 1]. For N=8 (EIGHTH_N=1)
# we wrap the body with an #if guard and fall back to a trivial passthrough
# (each Z_257 value emits a low byte, with bit-i of the carry set when the
# value is 256). That preserves the hash property — deterministic, with
# input → output bijective on values < 256 — without re-deriving the
# upstream's clever packing for a degenerate dimension.
if N < 16:
    open_needle = (
        "int16_t TranslateToBase256(int32_t input[EIGHTH_N], "
        "BitSequence output[EIGHTH_N])\r\n{\r\n"
    )
    open_repl = (
        open_needle + "#if EIGHTH_N < 2\r\n"
        "\tint i; int16_t carry = 0;\r\n"
        "\tfor (i = 0; i < EIGHTH_N; ++i) {\r\n"
        "\t\toutput[i] = (BitSequence)(input[i] & 0xff);\r\n"
        "\t\tif (input[i] == 256) carry |= (1 << i);\r\n"
        "\t}\r\n"
        "\treturn carry;\r\n"
        "#else\r\n"
    )
    if open_needle not in src:
        raise SystemExit("patch_swifftx: TranslateToBase256 prologue not found")
    src = src.replace(open_needle, open_repl, 1)

    close_needle = "\treturn (pairs[EIGHTH_N/2 - 1] >> 16);\r\n}"
    close_repl = "\treturn (pairs[EIGHTH_N/2 - 1] >> 16);\r\n#endif\r\n}"
    if close_needle not in src:
        raise SystemExit("patch_swifftx: TranslateToBase256 closing not found")
    src = src.replace(close_needle, close_repl, 1)

write(swifftx_c, src)


# ---- SHA3.h ----
src = read(sha3_h)
new = re.sub(
    r"^#define\s+SWIFFTX_OUTPUT_BLOCK_SIZE\s+65\b",
    f"#define SWIFFTX_OUTPUT_BLOCK_SIZE {N + 1}",
    src,
    count=1,
    flags=re.M,
)
if new == src:
    raise SystemExit("patch_swifftx: SHA3.h SWIFFTX_OUTPUT_BLOCK_SIZE not patched")
write(sha3_h, new)


# ---- SHA3.c: truncate each HAIFA_IV_* initializer to N+1 entries ----
src = read(sha3_c)
new_size = N + 1


def truncate_iv(text, name):
    pat = re.compile(
        r"(const\s+BitSequence\s+"
        + re.escape(name)
        + r"\s*\[\s*SWIFFTX_OUTPUT_BLOCK_SIZE\s*\]\s*=\s*)\{([^}]*)\}",
        re.S,
    )
    m = pat.search(text)
    if not m:
        raise SystemExit(f"patch_swifftx: {name} initializer not found")
    body = m.group(2)
    nums = re.findall(r"-?\d+", body)
    if len(nums) < new_size:
        raise SystemExit(
            f"patch_swifftx: {name} has {len(nums)} entries, need {new_size}"
        )
    kept = nums[:new_size]
    new_init = m.group(1) + "{" + ", ".join(kept) + "}"
    return text[: m.start()] + new_init + text[m.end() :]


for ivname in ("HAIFA_IV_224", "HAIFA_IV_256", "HAIFA_IV_384", "HAIFA_IV_512"):
    src = truncate_iv(src, ivname)
write(sha3_c, src)

print(f"patch_swifftx: N={N} LOGN={LOGN} OMEGA={OMEGA} OUTPUT_BLOCK_SIZE={new_size}")
