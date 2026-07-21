#!/bin/bash
# Approach A (reduce permutation rounds) per
# algorithm_scaling_down/nist_sha3/round_1/AURORA.txt and
# MEDIUM_VARIANTS_ADDENDUM.md:
#   Hard   (2^60-2^80): AURORA_ROUNDS = 10
#   Medium (2^40-2^60): AURORA_ROUNDS = 8
#   Easy   (2^30-2^40): AURORA_ROUNDS = 6
# Upstream baseline is AURORA_ROUNDS = 17 in
# AURORA/Reference_Implementation/aurora_ref.h.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same AURORA.zip name so
# build_cli.sh stays byte-identical to the base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="AURORA.zip"
EXTRACT_ROOT="AURORA"   # top-level dir inside the archive; patch -d resolves here

# band|round-count|patch-file
VARIANTS=(
    "easy|6|variant_easy.patch"
    "medium|8|variant_medium.patch"
    "hard|10|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}"
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
