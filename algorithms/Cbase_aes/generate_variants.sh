#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# Full AES-128 has 10 rounds. Simpler T2 variants: 4, 5, 6. Challenge (C_)
# ladder: 4, 5, 6, 7 (same simpler rounds plus the hardest, 7).
VARIANTS=("T2:4" "T2:5" "T2:6" "C:4" "C:5" "C:6" "C:7")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    sed -i "s/#define Nr 10/#define Nr ${r}/" "$VARIANT_DIR/environment/algorithm_src/aes.c"
done
