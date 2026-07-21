#!/usr/bin/env python3
"""ECHO medium variant patch: append a partial round (SubByte only).

Per variant_workfolder/final_fixes_recommendation.md (Section 2, "ECHO"),
the medium band sits between hard R=4 and easy R=3 by running R=3 full
rounds plus an extra SubByte-only step (no BigShiftRows / BigMixColumns /
key-mixing) appended to the round loop.

This script:
  1. Defines a new helper `BigSubBytesOnly` that applies the AES S-box
     (the existing `SubByte` function) to each of the 16 sub-blocks in
     `state->tab[i][j]`. No ShiftRows, no MixColumns, no AddRoundKey.
  2. Inserts a call to `BigSubBytesOnly(state);` inside `Compress`,
     immediately before `BigFinal(state);`.

The R=3 round count itself is set by the sed patch in build_cli.sh
(`state->rounds = 8;` -> `state->rounds = 3;` for hashbitlen <= 256).
"""

import sys

PATH = sys.argv[1]
src = open(PATH).read()

HELPER = """
void BigSubBytesOnly(hashState *state)
{
    int i, j;
    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++)
            SubByte(state->tab[i][j]);
}
"""

# Insert helper just before the definition of BigFinal so it precedes its
# only call site (inside Compress) -- the prototype isn't strictly needed
# because the call site sees its definition through the helper insertion
# only when it's inserted *before* Compress. Compress lives at line ~353,
# BigSubWords at ~409, BigFinal at ~544. To keep ordering sane, insert the
# helper just before `void Compress(hashState *state)` and add a forward
# prototype right after the existing prototypes block.

assert "void BigSubBytesOnly" not in src, "patch already applied"

# 1. Add forward prototype near the existing ones.
proto_anchor = "void Compress(hashState *state);"
assert proto_anchor in src, "Compress prototype not found"
src = src.replace(
    proto_anchor,
    proto_anchor + "\nvoid BigSubBytesOnly(hashState *state);",
    1,
)

# 2. Insert helper definition just before `void Compress(hashState *state)`.
def_anchor = "void Compress(hashState *state)\n{"
assert def_anchor in src, "Compress definition not found"
src = src.replace(def_anchor, HELPER + "\n" + def_anchor, 1)

# 3. Insert call just before `BigFinal(state);` inside Compress.
call_anchor = "\tBigFinal(state);"
assert src.count(call_anchor) == 1, "expected single BigFinal call site in Compress"
src = src.replace(
    call_anchor,
    "\tBigSubBytesOnly(state);\n" + call_anchor,
    1,
)

open(PATH, "w").write(src)
