#!/bin/bash
# Approach A (reduce JH ROUNDS) per
# algorithm_scaling_down/nist_sha3/round_3_finalists/JH_FinalRnd.txt and
# MEDIUM_VARIANTS_ADDENDUM.md (JH Final row).
# Upstream JH baseline: 42 rounds in E8 permutation.
#   Hard   (2^60-2^80): ROUNDS = 12
#   Medium (2^40-2^60): ROUNDS = 10
#   Easy   (2^30-2^40): ROUNDS = 8
#
# The JH reference (`jh_ref.h`) is header-only and has no `#define ROUNDS`
# macro -- the round count is the literal `42` in the loop bound
# `for (i = 0; i < 42; i++)` inside E8 (the only `i < 42` in the file).
#
# Concealment design: the weakening lives in committed root patch artifacts
# under ./variant_patches/ (a sibling of environment/, so they never enter
# the Docker build context => invisible to the agent). At generation time we
# unzip the variant's archive, apply the per-band patch to the extracted
# jh_ref.h, and repack into the SAME archive name. build_cli.sh is left
# byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="JH_FinalRnd.zip"
EXTRACT_ROOT="JH_FinalRnd"   # top-level dir inside the archive; patch -d target

# band|rounds|patch-file
VARIANTS=(
    "easy|8|variant_easy.patch"
    "medium|10|variant_medium.patch"
    "hard|12|variant_hard.patch"
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
    # extracted files are read-only in the archive; make writable so patch + repack work
    chmod -R u+w "$TMP/$EXTRACT_ROOT"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
