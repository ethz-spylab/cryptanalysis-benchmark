#!/usr/bin/env python3
"""Rewrite E2's encrypt/decrypt for variable R rounds.

Usage: patch_e2.py <R> <e2.c>

Upstream is R=12 (12 unrolled f_fun calls per direction with l_key
offsets 0,4,...,44). For R<12 we drop the trailing f_fun calls (those
whose l_key offset is >= 4*R). For odd R the f-chain leaves
(a,b,c,d) in swapped orientation relative to bp_fun's output, so
ibp_fun reassembles the wrong bytes; we insert a parity-correcting
swap (a,b)<->(c,d) immediately before ibp_fun in encrypt and
immediately after bp_fun in decrypt. The swap is its own inverse, so
encrypt-then-decrypt composes to identity for any R in {1..12}.
"""

import re
import sys

R = int(sys.argv[1])
PATH = sys.argv[2]
assert 1 <= R <= 12

SWAP = [
    "    { u4byte _t; _t = a; a = c; c = _t; _t = b; b = d; d = _t; }",
]

src = open(PATH).read()
lines = src.split("\n")
out = []
state = None
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
        m = re.search(r"f_fun\([^)]*l_key(?:\s*\+\s*(\d+))?\s*\)", line)
        if m:
            offset = int(m.group(1)) if m.group(1) else 0
            if offset >= 4 * R:
                i += 1
                continue
        if R % 2 == 1 and not swap_inserted:
            if state == "encrypt" and "ibp_fun(p, q, r, s" in line:
                out.extend(SWAP)
                swap_inserted = True
            elif state == "decrypt" and "bp_fun(a, b, c, d" in line:
                out.append(line)
                out.extend(SWAP)
                swap_inserted = True
                i += 1
                continue
        out.append(line)
    else:
        out.append(line)
    i += 1

open(PATH, "w").write("\n".join(out))
