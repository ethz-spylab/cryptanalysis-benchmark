#!/bin/bash
# Approach A (reduce BLAKE NB_ROUNDS32) per
# algorithm_scaling_down/nist_sha3/round_2/BLAKE_Round2.txt and
# MEDIUM_VARIANTS_ADDENDUM.md (BLAKE Final row).
# Upstream BLAKE-256 baseline: NB_ROUNDS32 = 14.
#   Hard   (2^60-2^80): ROUNDS = 6
#   Medium (2^40-2^60): ROUNDS = 5
#   Easy   (2^30-2^40): ROUNDS = 4
#
# Concealment design: the weakening is applied at GENERATION time by patching
# the upstream source INSIDE the variant's vendored archive and repacking it
# under the SAME archive name, so build_cli.sh stays byte-identical to base
# and no patch artifact ships in the Docker build context. The patch edits
# Blake_FinalRnd/Reference_Implementation/blake_ref.h (the header build_cli.sh
# copies to . and compiles); NB_ROUNDS64 is left at its upstream value (16)
# because our cli defaults to hashbitlen=256, which only invokes the 32-bit
# path. Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling
# of environment/, so they are outside the build context and invisible to the
# agent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Blake_FinalRnd.zip"

# band|rounds-encoding|patch-file
VARIANTS=(
    "easy|4|variant_easy.patch"
    "medium|5|variant_medium.patch"
    "hard|6|variant_hard.patch"
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
    chmod -R u+w "$TMP"
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
