#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="lotus-locus.zip"
EXTRACT_ROOT="lotus-locus"   # top-level dir inside the archive; patch -p1 resolves against it

# Approach A (reduce TweGIFT-64 CRYPTO_BC_NUM_ROUNDS) per
# algorithm_scaling_down/nist_lwc/round_1/lotus-locus.txt +
# MEDIUM_VARIANTS_ADDENDUM.md.
#   Hard   (2^60-2^80): R = 14
#   Medium (2^40-2^60): R = 12
#   Easy   (2^30-2^40): R =  9
# Upstream baseline is 28 rounds (lotus.h). TweGIFT-64's round constants come
# from a 7-bit LFSR and adapt to any R<=127.
#
# The weakening is applied at generation time: the variant's vendored archive is
# unzipped, the committed patch in ./variant_patches/ (which lives at the
# algorithm ROOT, outside environment/ => never enters the Docker build context)
# is applied, and the source is repacked into the SAME archive name so
# build_cli.sh stays byte-identical to the base.

# band|R|patch-file
A_VARIANTS=(
    "easy|9|variant_easy.patch"
    "medium|12|variant_medium.patch"
    "hard|14|variant_hard.patch"
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
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
