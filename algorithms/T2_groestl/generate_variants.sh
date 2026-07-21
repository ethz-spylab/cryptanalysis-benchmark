#!/bin/bash
# Approach A (reduce Groestl ROUNDS512) per
# algorithm_scaling_down/nist_sha3/round_3_finalists/Groestl_FinalRnd.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (Grostl row).
# Upstream: Groestl-ref.h defines `#define ROUNDS512 10` (used for
# hashbitlen <= 256, the cli's default) and `#define ROUNDS1024 14`.
#   Hard   (2^60-2^80): ROUNDS512 = 5
#   Medium (2^40-2^60): ROUNDS512 = 4
#   Easy   (2^30-2^40): ROUNDS512 = 3
#
# Concealment design (generation-time repack): Groestl-ref.h ships inside the
# upstream zip. We unzip the variant's archive, apply the band patch from
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent), repack into the SAME
# archive name so build_cli.sh stays byte-identical to base, and drop the
# patch artifacts from the variant.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Groestl_FinalRnd.zip"

# band|rounds|patch-file
VARIANTS=(
    "easy|3|variant_easy.patch"
    "medium|4|variant_medium.patch"
    "hard|5|variant_hard.patch"
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
    chmod -R u+w "$TMP"
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
