#!/bin/bash
# Approach A (reduce AES round count) per
# algorithm_scaling_down/nist_lwc/round_1/mixfeed.txt + MEDIUM_VARIANTS_ADDENDUM.md.
#   Hard   (2^60-2^80): R = 6  (loop bound j<7)
#   Medium (2^40-2^60): R = 5  (loop bound j<6, extended Square + key recovery)
#   Easy   (2^30-2^40): R = 4  (loop bound j<5)
# Upstream is the literal `for(int j = 1; j <11; j++)` loop in aes.h. The key
# schedule still walks 11 steps regardless of R, which is fine for the
# feedback-mode round-trip predicate.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never in the Docker build context => invisible to the agent).
# Each band's weakened source is repacked into the same mixfeed.zip name so
# build_cli.sh stays byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="mixfeed.zip"

# band|R|patch-file
A_VARIANTS=(
    "easy|4|variant_easy.patch"
    "medium|5|variant_medium.patch"
    "hard|6|variant_hard.patch"
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
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
