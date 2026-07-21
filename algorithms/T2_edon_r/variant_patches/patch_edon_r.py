#!/usr/bin/env python3
"""EDON-R medium/easy variant patch.

Drops the indicated row blocks from the unrolled compression in
`Edon-R_ref.c`. Per
variant_workfolder/final_fixes_recommendation.md (Section 2, "EDON-R"):

* Hard   (R = 8): all 4 rows kept (no patch).
* Medium (R = 6): drop row 3 → keep rows 1, 2, 4.
* Easy   (R = 4): drop rows 2 and 3 → keep rows 1, 4.

Row 4 always writes `p256[0..15]` / `p512[0..15]` — the slots that
`Final()` reads to produce the digest — so keeping it preserves the
pipe-slot contract regardless of how many earlier rows are present.

The same row blocks appear FOUR times in the file: in `Update()` for the
224/256 path and the 384/512 path, and in `Final()` for both paths. We
patch all four occurrences uniformly.

Usage: patch_edon_r.py <path-to-Edon-R_ref.c> <comma-separated row indices to drop>
"""

import re
import sys

PATH = sys.argv[1]
DROPS = {int(x) for x in sys.argv[2].split(",") if x}
ORDINALS = {1: "First", 2: "Second", 3: "Third", 4: "Fourth"}

src = open(PATH).read()

for row_idx in DROPS:
    word = ORDINALS[row_idx]
    # Each row block is a comment of the form
    #   /* <Word> row of quasigroup e-transformations */
    # followed by exactly two Q256(...) or Q512(...) macro calls (each
    # closed with `);`). Strip everything from the comment up to and
    # including the second `);` plus the trailing newline.
    pattern = re.compile(
        r"[ \t]*/\* " + word + r" row of quasigroup e-transformations \*/\s*"
        r"Q(?:256|512)\([^;]*?\);\s*"
        r"Q(?:256|512)\([^;]*?\);[ \t]*\n",
        re.DOTALL,
    )
    new_src, n = pattern.subn("", src)
    assert n == 4, f"Expected 4 occurrences of row {row_idx} ({word}), found {n}"
    src = new_src

open(PATH, "w").write(src)
