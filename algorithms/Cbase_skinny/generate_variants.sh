#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# Skinny-64-64 has 32 rounds. Simpler T2 variants: 10, 12, 14. Challenge (C_)
# ladder: 10, 12, 14, 17 (same simpler rounds plus the hardest, 17).
VARIANTS=("T2:10" "T2:12" "T2:14" "C:10" "C:12" "C:14" "C:17")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    sed -i "s/{64,64,32}/{64,64,${r}}/" "$VARIANT_DIR/environment/algorithm_src/skinny_reference.c"
done
