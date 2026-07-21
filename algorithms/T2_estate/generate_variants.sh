#!/bin/bash
# Approach A (round-reduce TweAES-128). Three security bands per the round-2
# spec + addendum:
#   - Hard   (2^60-2^80): CRYPTO_BC_NUM_ROUNDS = 6
#   - Medium (2^40-2^60): CRYPTO_BC_NUM_ROUNDS = 5
#   - Easy   (2^30-2^40): CRYPTO_BC_NUM_ROUNDS = 4
#
# AES round-constant table _aes_round_constants[10] covers up to 10 rounds,
# so any R <= 10 compiles cleanly. Mode A: estate.h is downloaded inside the
# upstream zip, so we patch it at generation time and repack the archive.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the SAME archive name so build_cli.sh
# stays byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="estate.zip"
EXTRACT_ROOT="estate"   # top-level dir inside the archive; the patch -p1 -d target

# band|rounds-encoding|patch-file
A_VARIANTS=(
    "easy|4|variant_easy.patch"
    "medium|5|variant_medium.patch"
    "hard|6|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
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
