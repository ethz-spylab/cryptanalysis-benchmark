#!/usr/bin/env python3
"""Patch Arirang_Ref64.c::Arirang_Compression256 to use R steps.

Usage: patch_arirang.py <R>      where R in {12, 15, 18, ...}.

The reference implementation unrolls 40 step256() calls with Feedforward_1
after step 20 and Feedforward_2 after step 40. We replace the whole
unrolled block with R step256 calls drawn from the same upstream order,
with Feedforward_1 inserted after step R/2 and Feedforward_2 retained at
the end. Feedforward_2 (`state->workingvar[i] ^= R[i]`) is the chaining-
state update; dropping it would freeze the IV across blocks.
"""

import re
import sys

R = int(sys.argv[1])
PATH = "Arirang_Ref64.c"

# Upstream step256(R, W[a], W[b]) sequence in declaration order (40 entries).
STEPS = [
    (16, 17),
    (0, 1),
    (2, 3),
    (4, 5),
    (6, 7),
    (18, 19),
    (8, 9),
    (10, 11),
    (12, 13),
    (14, 15),
    (20, 21),
    (3, 6),
    (9, 12),
    (15, 2),
    (5, 8),
    (22, 23),
    (11, 14),
    (1, 4),
    (7, 10),
    (13, 0),
    (24, 25),
    (12, 5),
    (14, 7),
    (0, 9),
    (2, 11),
    (26, 27),
    (4, 13),
    (6, 15),
    (8, 1),
    (10, 3),
    (28, 29),
    (7, 2),
    (13, 8),
    (3, 14),
    (9, 4),
    (30, 31),
    (15, 10),
    (5, 0),
    (11, 6),
    (1, 12),
]

if R < 2 or R > 40 or R % 2 != 0:
    sys.exit("patch_arirang.py: R must be even, 2..40 (got %d)" % R)

half = R // 2

with open(PATH) as f:
    src = f.read()

# Replace the block from "// 1 Round" through and including "// Feedforward_2 ..."
# loop with the parameterised version. Anchor on the FF2 loop end so we keep
# the trailing `state->counter[0]++;`.
m = re.search(
    r"(\n\t// 1 Round\n)(.*?)(\tfor\(i=0;i<8;i\+\+\)\s*state->workingvar\[i\] \^= R\[i\];\n)",
    src,
    re.DOTALL,
)
if not m:
    sys.exit("patch_arirang.py: could not locate compression block in %s" % PATH)

lines = []
for idx, (a, b) in enumerate(STEPS[:R]):
    lines.append("\tstep256(R, W[%2d], W[%2d]);" % (a, b))
    if idx + 1 == half:
        lines.append("")
        lines.append("\t// Feedforward_1")
        lines.append("\tfor(i=0;i<8;i++)\tR[i] ^= state->workingvar[i];")
        lines.append("")

new_block = "\n\t// Compression rounds (R=%d, FF1 at step %d)\n" % (R, half)
new_block += "\n".join(lines) + "\n\n"
new_block += "\t// Feedforward_2\n"
new_block += "\tfor(i=0;i<8;i++)\tstate->workingvar[i] ^= R[i];\n"

new_src = src[: m.start()] + new_block + src[m.end() :]

with open(PATH, "w") as f:
    f.write(new_src)

print("patch_arirang.py: wrote R=%d compression (FF1 at step %d)" % (R, half))
