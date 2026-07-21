#!/bin/bash
# Approach A (reduce CRYPTO_BC_NUM_ROUNDS) per
# algorithm_scaling_down/nist_lwc/round_1/trifle.txt and the medium value from
# MEDIUM_VARIANTS_ADDENDUM.md:
#   - Hard   (2^60-2^80): R = 33
#   - Medium (2^40-2^60): R = 30
#   - Easy   (2^30-2^40): R = 26
#
# Upstream Round-1 reference: R = 50; the round-constant table
# `_casb_round_constants[62]` covers any R <= 62.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same archive name so build_cli.sh
# stays byte-identical to the base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="trifle.zip"
EXTRACT_ROOT="trifle"   # top-level dir inside the archive (patch paths are a/$EXTRACT_ROOT/...)

# band|R-encoding|patch-file
A_VARIANTS=(
    "easy|26|variant_easy.patch"
    "medium|30|variant_medium.patch"
    "hard|33|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    # patch paths are a/$EXTRACT_ROOT/...; -p1 strips a/ leaving $EXTRACT_ROOT/... under $TMP
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"
    rm -rf "$VARIANT_DIR/variant_patches"
done
