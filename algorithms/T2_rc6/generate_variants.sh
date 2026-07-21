#!/bin/bash
# Approach A: reduce ROUNDS in RC6's aes.h.
# Bands per algorithm_scaling_down/nist_aes/round_2_finalists/RC6.txt + addendum:
#   Hard (2^60-2^80): ROUNDS = 6
#   Medium (2^40-2^60): ROUNDS = 5
#   Easy (2^30-2^40): ROUNDS = 4
# Upstream baseline: ROUNDS = 20.
#
# Concealment design: the weakening is applied at GENERATION time by repacking
# the variant's own archive, never by injecting into build_cli.sh (which stays
# byte-identical to base). Patch artifacts live in ./variant_patches/ at the
# algorithm ROOT (sibling of environment/), so they never enter the Docker build
# context and are stripped from each variant after use.
#
# Archive nesting: RC6-AES-2.zip contains rc6-dos-refc.tar, which contains
# RC6/aes.h (the file holding the ROUNDS constant). build_cli.sh unzips the zip
# then untars rc6-dos-refc.tar and copies RC6/aes.h -> cipher.h, so the patched
# value must be repacked through both layers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="RC6-AES-2.zip"
INNER_TAR="rc6-dos-refc.tar"

# band|round-value|patch-file
A_VARIANTS=(
    "easy|4|variant_easy.patch"
    "medium|5|variant_medium.patch"
    "hard|6|variant_hard.patch"
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

    # Layer 1: unzip the variant's archive (yields the inner tars).
    unzip -q -o "$ARCH" -d "$TMP"

    # Layer 2: extract the inner tar holding RC6/aes.h, patch, re-tar in place.
    EXTRACT="$TMP/extract"
    mkdir -p "$EXTRACT"
    tar -xf "$TMP/$INNER_TAR" -C "$EXTRACT"
    patch -p1 -d "$EXTRACT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$EXTRACT" && rm -f "$TMP/$INNER_TAR" && tar -cf "$TMP/$INNER_TAR" RC6 )
    rm -rf "$EXTRACT"

    # Repack the zip with the same internal layout build_cli.sh expects.
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )

    rm -rf "$TMP"
    rm -rf "$VARIANT_DIR/variant_patches"
done
