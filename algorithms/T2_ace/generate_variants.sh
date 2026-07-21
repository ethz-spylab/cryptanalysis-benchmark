#!/bin/bash
# Approach A (reduce ACE NUMSTEPS) per
# algorithm_scaling_down/nist_lwc/round_2/ace.txt and
# MEDIUM_VARIANTS_ADDENDUM.md (ace row).
# Upstream: ace.h defines `#define NUMSTEPS 16` (number of permutation steps).
#   Hard   (2^60-2^80): NUMSTEPS = 5
#   Medium (2^40-2^60): NUMSTEPS = 4
#   Easy   (2^30-2^40): NUMSTEPS = 3
#
# Concealment design: the weakening is applied at generation time by unzipping
# the variant's own copy of ace.zip, patching ace.h with a committed patch from
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent), and repacking into the same
# archive name. build_cli.sh stays byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="ace.zip"
EXTRACT_ROOT="ace"   # top-level dir inside ace.zip

# band|steps-encoding|patch-file
VARIANTS=(
    "easy|3|variant_easy.patch"
    "medium|4|variant_medium.patch"
    "hard|5|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND STEPS PATCH <<< "$entry"
    SUFFIX="${BAND}_s${STEPS}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" "$EXTRACT_ROOT" )
    chmod -R u+w "$TMP"
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
