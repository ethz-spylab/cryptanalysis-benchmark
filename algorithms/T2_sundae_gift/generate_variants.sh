#!/bin/bash
# Approach A (reduce GIFT-128 ROUNDS) per
# algorithm_scaling_down/nist_lwc/round_2/sundae-gift.txt and
# MEDIUM_VARIANTS_ADDENDUM.md:
#   Hard   (2^60-2^80): ROUNDS = 14
#   Medium (2^40-2^60): ROUNDS = 12
#   Easy   (2^30-2^40): ROUNDS = 9
# Upstream baseline: 40 rounds.
#
# The reference impl has no #define ROUNDS — the round count is the literal
# `40` in `for(round=0; round<40; round++)` in gift128.c.
#
# Concealment design: patch artifacts live in ./variant_patches/ (algorithm
# ROOT, outside environment/ => never in the Docker build context => invisible
# to the agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays byte-identical to the base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="sundae-gift.zip"
EXTRACT_ROOT="sundae-gift"   # top-level dir inside the archive

# band|rounds|patch-file
VARIANTS=(
    "easy|9|variant_easy.patch"
    "medium|12|variant_medium.patch"
    "hard|14|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND ROUNDS PATCH <<< "$entry"
    SUFFIX="${BAND}_r${ROUNDS}"
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
