#!/usr/bin/env python3
"""Shabal variant patch: decouple inner-permutation loop bound from sM.

Per variant_workfolder/final_fixes_recommendation.md (Section 2,
"Shabal"), the upstream `sM` macro doubles as both the message-block
width (16 u32 words) and the inner-permutation loop bound. Macro flips
of SHABAL_PARAM_P alone reach only {16, 32, 48} total inner ops, none
of which match the spec's hard / medium / easy targets.

Fix: introduce a new compile-time constant SHABAL_ROUNDS_PER_BLOCK and
rewrite the inner-permutation loop in `apply_perm()` so it iterates
SHABAL_ROUNDS_PER_BLOCK times per outer step, walking the column index
*backwards* from sM - 1. This biases the partial work toward the high
columns of state->B, which are the columns the hash-output truncation
reads (Final() emits B[sM - hashbitlen/32 .. sM - 1]). With the
forward-walk literally specified by the recipe, RPB < sM leaves the
high columns of B untouched and the hash output is constant
irrespective of input; the backward walk preserves output diffusion at
small RPB.

The textually-identical twin loop above (which rotates state->B
in-place and is tied to the message-block layout) keeps `sM` as its
bound. We disambiguate by anchoring on the unique `u32 tB` body
declaration of the inner-permutation loop.

Variant tuples are baked directly into the extracted source: this patch
takes the band's P and ROUNDS_PER_BLOCK as argv and writes them into the
macro defaults, so build_cli.sh stays byte-identical to the base task
(no `-D` flags are injected). The structural loop rewrite is identical
for every band; only the two macro default values differ.

Usage:
  python3 patch_shabal.py <path-to-shabal.c> <P> <RPB>
"""

import sys

PATH = sys.argv[1]
P = int(sys.argv[2])
RPB = int(sys.argv[3])
with open(PATH, "rb") as f:
    raw = f.read()
crlf = b"\r\n" in raw
src = raw.decode("latin-1").replace("\r\n", "\n")

assert "SHABAL_ROUNDS_PER_BLOCK" not in src, "patch already applied"

# 0. Bake the band's SHABAL_PARAM_P into the upstream macro default
#    (replacing the spec default of 3), so the value travels with the
#    repacked source instead of via a `-D` compiler flag.
PARAM_P_ANCHOR = "#ifndef SHABAL_PARAM_P\n#define SHABAL_PARAM_P   3\n#endif\n"
PARAM_P_REPLACE = (
    "#ifndef SHABAL_PARAM_P\n#define SHABAL_PARAM_P   %d\n#endif\n" % P
)
assert PARAM_P_ANCHOR in src, "SHABAL_PARAM_P default block not found"
src = src.replace(PARAM_P_ANCHOR, PARAM_P_REPLACE, 1)

# 1. Add a default for SHABAL_ROUNDS_PER_BLOCK alongside the other macro
#    defaults, set to the band's RPB value. (Upstream couples the inner-
#    permutation loop bound to sM = 16; this decouples it.)
DEFAULTS_ANCHOR = "#ifndef SHABAL_PARAM_E\n#define SHABAL_PARAM_E   3\n#endif\n"
DEFAULTS_INSERT = (
    "#ifndef SHABAL_ROUNDS_PER_BLOCK\n#define SHABAL_ROUNDS_PER_BLOCK   %d\n#endif\n"
    % RPB
)
assert DEFAULTS_ANCHOR in src, "SHABAL_PARAM_E default block not found"
src = src.replace(
    DEFAULTS_ANCHOR,
    DEFAULTS_ANCHOR + DEFAULTS_INSERT,
    1,
)

# 2. Replace the inner-permutation loop body. Anchor is the unique
#    `for (i = 0; i < sM; i ++) {\n\t\t\tu32 tB;` two-line context.
INNER_OLD = (
    "\t\tfor (i = 0; i < sM; i ++) {\n"
    "\t\t\tu32 tB;\n"
    "\n"
    "\t\t\txA = U(xA ^ V(T32(xAm1 << 15) | (xAm1 >> 17))\n"
    "\t\t\t\t\t^ state->C[(8 + sM - i) % sM])\n"
    "\t\t\t\t^ state->B[(i + O1) % sM]\n"
    "\t\t\t\t^ (state->B[(i + O2) % sM]\n"
    "\t\t\t\t\t& ~state->B[(i + O3) % sM])\n"
    "\t\t\t\t^ m[i];\n"
    "\t\t\ttB = state->B[i];\n"
    "\t\t\tstate->B[i] = T32(((tB << 1) | (tB >> 31)) ^ ~xA);\n"
    "\t\t}\n"
)
INNER_NEW = (
    "\t\t{\n"
    "\t\t\tint kk;\n"
    "\t\t\tfor (kk = 0; kk < SHABAL_ROUNDS_PER_BLOCK; kk ++) {\n"
    "\t\t\t\tu32 tB;\n"
    "\t\t\t\t/* Walk i backwards from sM-1 so the partial work (when\n"
    "\t\t\t\t * SHABAL_ROUNDS_PER_BLOCK < sM) covers the high columns of\n"
    "\t\t\t\t * state->B that Final() reads as the hash output. */\n"
    "\t\t\t\ti = (sM - 1) - ((j * SHABAL_ROUNDS_PER_BLOCK + kk) % sM);\n"
    "\t\t\t\txA = U(xA ^ V(T32(xAm1 << 15) | (xAm1 >> 17))\n"
    "\t\t\t\t\t\t^ state->C[(8 + sM - i) % sM])\n"
    "\t\t\t\t\t^ state->B[(i + O1) % sM]\n"
    "\t\t\t\t\t^ (state->B[(i + O2) % sM]\n"
    "\t\t\t\t\t\t& ~state->B[(i + O3) % sM])\n"
    "\t\t\t\t^ m[i];\n"
    "\t\t\t\ttB = state->B[i];\n"
    "\t\t\t\tstate->B[i] = T32(((tB << 1) | (tB >> 31)) ^ ~xA);\n"
    "\t\t\t}\n"
    "\t\t}\n"
)
assert INNER_OLD in src, "inner-permutation loop full anchor not found"
src = src.replace(INNER_OLD, INNER_NEW, 1)

if crlf:
    src = src.replace("\n", "\r\n")
with open(PATH, "wb") as f:
    f.write(src.encode("latin-1"))
