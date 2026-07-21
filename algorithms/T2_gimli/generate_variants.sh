#!/bin/bash
# Approach A (reduce Gimli permutation rounds) per
# algorithm_scaling_down/nist_lwc/round_2/gimli.txt + addendum:
#   Hard   (2^60-2^80): R = 16
#   Medium (2^40-2^60): R = 15
#   Easy   (2^30-2^40): R = 14
# Upstream baseline: 24 rounds in gimli/Implementations/.../ref/gimli.inc.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside environment/
# => never in the Docker build context => invisible to the agent). The weakened
# source is repacked into the same archive name (gimli.zip) so build_cli.sh stays
# byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="gimli.zip"
EXTRACT_ROOT="gimli"   # top-level dir inside the archive; patch -p1 resolves here

# band|round-value|patch-file
A_VARIANTS=(
    "easy|14|variant_easy.patch"
    "medium|15|variant_medium.patch"
    "hard|16|variant_hard.patch"
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
