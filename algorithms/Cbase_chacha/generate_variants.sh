#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# ChaCha8 has 8 rounds. The reference loop counts down by 2 (one double round
# per iteration). To support odd round counts we rewrite it as an ascending
# loop and add an early `break` between the column round and the diagonal
# round so r odd stops after the column half. Verified: r=8 produces the same
# keystream as the unpatched implementation; round-trip works for any r.
#
# Simpler T2 variants: 2, 4, 6 rounds. Challenge (C_) ladder: 2, 4, 6, 7
# (same simpler rounds plus the hardest, 7).
VARIANTS=("T2:2" "T2:4" "T2:6" "C:2" "C:4" "C:6" "C:7")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    SRC="$VARIANT_DIR/environment/algorithm_src/chacha.c"
    sed -i "s|for (i = 8;i > 0;i -= 2)|for (i = 0; i < ${r}; i += 2)|" "$SRC"
    sed -i "/QUARTERROUND( 3, 7,11,15)/a\\    if (i + 1 >= ${r}) break;" "$SRC"
done
