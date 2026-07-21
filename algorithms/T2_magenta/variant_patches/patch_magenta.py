#!/usr/bin/env python3
"""Rewrite MAGENTA's set_key case 2, encrypt, decrypt for variable R rounds.

Usage: patch_magenta.py <R> <magenta.c>

Supported R: 2, 4, 6 (must be even). R=6 is the upstream default.
For each R, l_key[0..2*R-1] is filled with a palindromic key sequence so
that encrypt and decrypt (which apply identical r_fun call sequences)
remain mutually inverse.
"""

import re
import sys

R = int(sys.argv[1])
PATH = sys.argv[2]
assert R in (2, 4, 6), f"unsupported R={R}"

# Palindromic key index for R rounds: each entry names the half of in_key
# (0 -> in_key[0..1], 2 -> in_key[2..3]) used by that round's two l_key
# slots.
PALINDROMES = {
    6: [0, 0, 2, 2, 0, 0],  # AABBAA — upstream
    4: [0, 2, 2, 0],  # ABBA
    2: [0, 0],  # AA
}
halves = PALINDROMES[R]

case2 = "        case 2:\n"
for i, h in enumerate(halves):
    case2 += (
        f"            l_key[{2 * i:2d}] = in_key[{h}]; "
        f"l_key[{2 * i + 1:2d}] = in_key[{h + 1}]; \n"
    )
case2 += "            break;\n"

rounds = ""
for i in range(R):
    if i % 2 == 0:
        rounds += f"    r_fun(blk, blk + 2, l_key + {2 * i:2d});\n"
    else:
        rounds += f"    r_fun(blk + 2, blk, l_key + {2 * i:2d});\n"

src = open(PATH).read()

src = re.sub(
    r"        case 2:\n(?:.*\n)*?            break;\n",
    case2,
    src,
    count=1,
)


def replace_block(text, start_pat, end_pat, replacement):
    m1 = re.search(start_pat, text)
    if m1 is None:
        raise SystemExit(f"start pattern not found: {start_pat!r}")
    rest = text[m1.end() :]
    m2 = re.search(end_pat, rest)
    if m2 is None:
        raise SystemExit(f"end pattern not found: {end_pat!r}")
    return text[: m1.end()] + replacement + rest[m2.start() :]


# encrypt: replace round body between the input copy and the k_len==4 guard.
src = replace_block(
    src,
    r"    blk\[0\] = in_blk\[0\]; blk\[1\] = in_blk\[1\];\n"
    r"    blk\[2\] = in_blk\[2\]; blk\[3\] = in_blk\[3\];\n",
    r"    if\(k_len == 4\)",
    "    \n" + rounds + "\n",
)

# decrypt: replace round body between the swapped input copy and the guard.
src = replace_block(
    src,
    r"    blk\[2\] = in_blk\[0\]; blk\[3\] = in_blk\[1\];\n"
    r"    blk\[0\] = in_blk\[2\]; blk\[1\] = in_blk\[3\];\n",
    r"    if\(k_len == 4\)",
    "\n" + rounds + "\n",
)

open(PATH, "w").write(src)
