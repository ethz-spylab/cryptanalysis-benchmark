#!/usr/bin/env python3
"""Truncate SANDstorm's unrolled inner-round block.

Upstream `Do_Block_ModMix_Ref` in SHA3api_ref.c contains five unrolled round
blocks ("// Round 0" .. "// Round 4"), followed by the TSP extension loop and
`round4_out`. This script keeps the first R unrolled rounds (R in {2,3,4}) and
deletes rounds R..4. The TSP loop and `round4_out` are preserved.

Each surviving round-N block populates `prevBlockArr[N+1]`. The TSP loop /
`round4_out` fills `prevBlockArr[4]`. If R < 3, `prevBlockArr[3]` would be left
at its compile-time constant — different messages then collide on the bits the
digest extracts from that slot, breaking diffusion without telling the
attacker any new fact. We patch in a linear `round_out` chain that rides the
last surviving round's `ws[]` into the abandoned slot. This adds zero
non-linear work (the recipe's "feedforward-style XOR that remains correct
regardless of inner round count" reading), and ensures every output slot
depends on the input.

Usage: patch_sandstorm.py <R> <path/to/SHA3api_ref.c>
"""

import sys

R = int(sys.argv[1])
if R not in (2, 3, 4):
    raise SystemExit(f"patch_sandstorm: unsupported R={R}")
path = sys.argv[2]

with open(path, "rb") as f:
    raw = f.read()
text = raw.decode("latin-1")

start_marker = f"// Round {R}"
end_marker = "// Extended Security Rounds"

start = text.find(start_marker)
end = text.find(end_marker)
if start == -1 or end == -1 or end <= start:
    raise SystemExit(f"patch_sandstorm: markers not found (start={start}, end={end})")

# Walk back to the start of the line containing "// Round R".
prev_newline = text.rfind("\n", 0, start)
if prev_newline != -1:
    start = prev_newline + 1

# For R == 2, populate the abandoned prevBlockArr[3] slot linearly so the
# digest reads input-dependent bits there.
if R == 2:
    extra = "\tround_out(prevBlockArr[3], prevBlockArr[2]);\r\n\r\n\t"
else:
    extra = ""

new_text = text[:start] + extra + text[end:]
with open(path, "wb") as f:
    f.write(new_text.encode("latin-1"))

print(f"patch_sandstorm: kept rounds 0..{R - 1}; deleted rounds {R}..4")
