#!/bin/bash
# Approach A (reduce WAGEROUNDS) variants for WAGE.
#   - Hard   (2^60-2^80): WAGEROUNDS=65   (per-algorithm spec)
#   - Medium (2^40-2^60): WAGEROUNDS=57   (MEDIUM_VARIANTS_ADDENDUM.md)
#   - Easy   (2^30-2^40): WAGEROUNDS=50   (per-algorithm spec)
#
# wage.h ships only inside the upstream wage.zip pulled by build_cli.sh. The
# weakening is applied at GENERATION time: unzip the variant's archive copy,
# apply the band patch from ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent),
# repack into the SAME archive name so build_cli.sh stays byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="wage.zip"
EXTRACT_ROOT="wage"   # top-level dir inside the archive; patch -p1 resolves against it

# band|rounds-encoding|patch-file
A_VARIANTS=(
    "easy|50|variant_easy.patch"
    "medium|57|variant_medium.patch"
    "hard|65|variant_hard.patch"
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
