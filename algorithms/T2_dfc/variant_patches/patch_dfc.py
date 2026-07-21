#!/usr/bin/env python3
"""Rewrite DFC's encrypt/decrypt for variable R rounds.

Usage: patch_dfc.py <R> <dfc.c>

Upstream is R=8 (8 unrolled r_fun calls per direction with l_key offsets
0,4,...,28). For R<8 we drop the trailing r_fun calls (those whose
l_key offset is >= 4*R). For odd R the f-chain leaves blk halves in
the wrong orientation for the output half-swap; we insert a
parity-correcting swap blk[0]<->blk[2], blk[1]<->blk[3] before the
output writes in encrypt and right after the input reads in decrypt.
The swap is its own inverse, so encrypt-then-decrypt composes to
identity for any R in {1..8}.
"""

import re
import sys

R = int(sys.argv[1])
PATH = sys.argv[2]
assert 1 <= R <= 8

SWAP = [
    "    { u4byte _t = blk[0]; blk[0] = blk[2]; blk[2] = _t;",
    "      _t = blk[1]; blk[1] = blk[3]; blk[3] = _t; }",
]

src = open(PATH).read()
lines = src.split("\n")
out = []
state = None  # "encrypt" / "decrypt" / None
swap_inserted = False

i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith("void encrypt("):
        state = "encrypt"
        swap_inserted = False
        out.append(line)
    elif line.startswith("void decrypt("):
        state = "decrypt"
        swap_inserted = False
        out.append(line)
    elif state and line.strip() == "};":
        state = None
        out.append(line)
    elif state:
        m = re.search(r"r_fun\([^)]*l_key(?:\s*\+\s*(\d+))?\s*\)", line)
        if m:
            offset = int(m.group(1)) if m.group(1) else 0
            if offset >= 4 * R:
                i += 1
                continue
        if R % 2 == 1 and not swap_inserted:
            if state == "encrypt" and "/* swap order to obtain the result" in line:
                out.extend(SWAP)
                out.append("")
                swap_inserted = True
            elif state == "decrypt" and "blk[2] = io_swap(in_blk[2])" in line:
                out.append(line)
                out.append("")
                out.extend(SWAP)
                out.append("")
                swap_inserted = True
                i += 1
                continue
        out.append(line)
    else:
        out.append(line)
    i += 1

open(PATH, "w").write("\n".join(out))
