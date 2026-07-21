#!/bin/bash
# Approach A (reduce per-block ROUNDS) per
# algorithm_scaling_down/nist_lwc/round_1/gage-ingage.txt and
# MEDIUM_VARIANTS_ADDENDUM.md:
#   Hard   (2^60-2^80): ROUNDS = 18
#   Medium (2^40-2^60): ROUNDS = 15
#   Easy   (2^30-2^40): ROUNDS = 12
#
# Constant lives in `parameters.h` of the ingage1k128n096c224r008 ref
# (default 32). MAX_ROUNDS=116 (init/finalise) is left untouched per the
# spec's Approach-A guidance.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays byte-identical to base (no build-time injection).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="gage-ingage.zip"

# band|round-count|patch-file
A_VARIANTS=(
    "easy|12|variant_easy.patch"
    "medium|15|variant_medium.patch"
    "hard|18|variant_hard.patch"
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
