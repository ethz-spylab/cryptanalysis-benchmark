#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# KATAN32 has 254 rounds. Simpler T2 variants: 60, 85, 110. Challenge (C_)
# ladder: 60, 85, 110, 124 (same simpler rounds plus the hardest, 124).
VARIANTS=("T2:60" "T2:85" "T2:110" "C:60" "C:85" "C:110" "C:124")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    sed -i "s/#define KATAN_ROUNDS 254/#define KATAN_ROUNDS ${r}/" "$VARIANT_DIR/environment/algorithm_src/katan.h"

    # Fix VLA size in katan.c: the key schedule always copies 80 key bits,
    # so the k[] array must be at least 80 elements even for reduced rounds.
    sed -i 's/k\[2\*rounds\]/k[2*rounds < 80 ? 80 : 2*rounds]/g' "$VARIANT_DIR/environment/algorithm_src/katan.c"
done
