#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

# Approach A (reduce number of permutation steps for the 256-bit hash, the
# default hashbitlen used by the harness).
#   - Hard   (2^60-2^80): _256_STEPS = 12  -- per CHI.txt
#   - Medium (2^40-2^60): _256_STEPS = 10  -- per addendum
#   - Easy   (2^30-2^40): _256_STEPS = 8   -- per CHI.txt
# Upstream default is _256_STEPS = 20.
#
# Generation-time repack: the per-band patch artifacts live in
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never enters
# the Docker build context => invisible to the agent). For each band we unzip
# the variant's copy of the archive, apply the patch to chi.h, and repack into
# the SAME archive name so build_cli.sh stays byte-identical to base.

SRC_REL="environment/algorithm_src"
ARCHIVE="CHIUpdate.zip"
EXTRACT_ROOT="CHI"   # top-level dir inside the archive

# band|steps-encoding|patch-file
VARIANTS=(
    "easy|8|variant_easy.patch"
    "medium|10|variant_medium.patch"
    "hard|12|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND STEPS PATCH <<< "$entry"
    SUFFIX="${BAND}_steps${STEPS}"
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
