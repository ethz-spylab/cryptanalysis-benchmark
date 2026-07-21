#!/usr/bin/env python3
"""LANE medium variant patch: append a partial round to PermuteP256.

Per variant_workfolder/final_fixes_recommendation.md (Section 2, "LANE"),
the medium band sits between hard R=4 and easy R=3 by running R=3
full rounds (loop bound `i!=2` plus the existing special last round) and
appending a partial round (SubBytes + ShiftRows only, no MixColumns and
no SwapColumns) at the end of PermuteP256.

The R=3 base is delivered by the sed patch in build_cli.sh (`i!=5` ->
`i!=2`). This script appends the partial-round call pair just before the
closing `}` of PermuteP256.
"""

import sys
import re

PATH = sys.argv[1]
src = open(PATH).read()

# PermuteP256 ends after the final SwapColumns256 + its trailing #ifdef
# debug block. We anchor on the unique tail comment block of that
# function -- the second SwapColumns256(a); inside PermuteP256 is the
# very last operation before the closing brace.
#
# Find PermuteP256's body and inject before the final closing `}`.
m = re.search(
    r"(void PermuteP256\([^{]*\{)",
    src,
)
assert m, "PermuteP256 signature not found"
start = m.end()

# Walk braces to find the matching close.
depth = 1
i = start
while i < len(src) and depth > 0:
    c = src[i]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
assert depth == 0, "PermuteP256 closing brace not found"
close_idx = i

INSERT = """
  /* LANE medium-variant partial round: SubBytes + ShiftRows only. */
  SubBytes256(a);
  ShiftRows256(a);
"""

src = src[:close_idx] + INSERT + src[close_idx:]
open(PATH, "w").write(src)
