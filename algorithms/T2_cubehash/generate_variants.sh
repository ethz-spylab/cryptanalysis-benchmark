#!/bin/bash
# Approach A (reduce r per CubeHash-r/b) per
#   algorithm_scaling_down/nist_sha3/round_2/CubeHash_Round2.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (hard=5, medium=4, easy=3).
#
# Mode: generation-time patch + repack. The reference defines
# `#define CUBEHASH_ROUNDS 16` at the top of
# CubeHash/Reference_Implementation/cubehash.c (this is `r` for
# CubeHash-r/b); reducing it scales the per-block round count.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays byte-identical to the base task.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="CubeHash_Round2.zip"

# band|param-encoding|patch-file
VARIANTS=(
    "easy|r3|variant_easy.patch"
    "medium|r4|variant_medium.patch"
    "hard|r5|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    # Patch paths are a/CubeHash/... b/CubeHash/... => -p1 against $TMP root.
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
