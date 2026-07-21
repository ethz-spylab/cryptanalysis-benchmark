#!/bin/bash
# Approach A (simplify F1: number of expansion_1 steps out of 16 total) per
# algorithm_scaling_down/nist_sha3/round_1/Blue_Midnight_Wish.txt
#   Hard   EXPAND_1_ROUNDS=8  EXPAND_2_ROUNDS=8   (2^60-2^80)
#   Medium EXPAND_1_ROUNDS=6  EXPAND_2_ROUNDS=10  (2^40-2^60, per addendum)
#   Easy   EXPAND_1_ROUNDS=4  EXPAND_2_ROUNDS=12  (2^30-2^40)
# Upstream default is EXPAND_1_ROUNDS=2 / EXPAND_2_ROUNDS=14.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened SHA3api_ref.h is repacked into the same archive name so
# build_cli.sh stays byte-identical to the base task.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Blue_Midnight_Wish_Round2.zip"
EXTRACT_ROOT="Blue_Midnight_Wish"   # top-level dir inside the archive

# band|expand_1-encoding|patch-file
VARIANTS=(
    "easy|4|variant_easy.patch"
    "medium|6|variant_medium.patch"
    "hard|8|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND E1 PATCH <<< "$entry"
    SUFFIX="${BAND}_e1_${E1}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
