#!/usr/bin/env python3
"""MCSSHA-3 medium/easy variant patch.

Reduces the per-byte delay-loop bound in `mcssha3.c::Update`. Per
algorithm_scaling_down/nist_sha3/round_1/MCSSHA3.txt and
variant_workfolder/final_fixes_recommendation.md (Section 2, "MCSSHA-3"):

* Hard   (delay = 3): unmodified upstream (no patch).
* Medium (delay = 2): ~25% less per-byte work.
* Easy   (delay = 1): ~50% less per-byte work.

The delay loop appears exactly once in the file as the literal
`for(k=0;k<3;k++)`. We rewrite the loop bound to the band's value.

Usage: patch_mcssha3.py <path-to-mcssha3.c> <delay>
"""

import sys

PATH = sys.argv[1]
DELAY = int(sys.argv[2])

src = open(PATH).read()
old = "for(k=0;k<3;k++)"
new = f"for(k=0;k<{DELAY};k++)"

count = src.count(old)
assert count == 1, f"Expected exactly 1 occurrence of {old!r}, found {count}"

src = src.replace(old, new)
open(PATH, "w").write(src)
