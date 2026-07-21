#!/bin/bash
# Approach A: round-reduce primary TK3 SKINNY-128-384 (used by
# skinnyaeadtk396128v1, the M1 primary AEAD member) per
# nist_lwc/round_2/skinny.txt (per-round gain ~2^15-2^25):
#   Hard (2^60-2^80) R=18  Medium (2^40-2^60) R=16  Easy (2^30-2^40) R=14
#
# Patch: in skinny_reference.c, the row {128,384, 56} -> {128,384, R}.
# `RC[]` covers up to 62 rounds, so reductions are safe.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays byte-identical to the base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="skinny.zip"
EXTRACT_ROOT="skinny"   # top-level dir inside skinny.zip; patch -p1 -d resolves against it

# band|R|patch-file
A_VARIANTS=(
    "easy|14|variant_easy.patch"
    "medium|16|variant_medium.patch"
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
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
