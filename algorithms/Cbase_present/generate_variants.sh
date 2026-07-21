#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# PRESENT-80 has 31 processing rounds + 1 final key addition (32 total).
# Simpler T2 variants: 8, 10, 12. Challenge (C_) ladder: 8, 10, 12, 29
# (same simpler rounds plus the hardest, 29).
VARIANTS=("T2:8" "T2:10" "T2:12" "C:8" "C:10" "C:12" "C:29")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    SRC="$VARIANT_DIR/environment/algorithm_src/cli.cpp"

    # Change encrypt & decrypt loop bounds: "i < 31; i++)" -> "i < r; i++)"
    sed -i "s/i < 31; i++)/i < ${r}; i++)/" "$SRC"

    # Change final encrypt subkey index: subkey[31] -> subkey[r]
    sed -i "s/\\*state ^= subkey\\[31\\]/*state ^= subkey[${r}]/" "$SRC"

    # Change decrypt starting key index: keyindex = 31 -> keyindex = r
    sed -i "s/keyindex = 31/keyindex = ${r}/" "$SRC"
done
