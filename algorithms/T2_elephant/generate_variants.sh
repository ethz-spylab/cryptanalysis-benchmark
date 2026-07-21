#!/bin/bash
# Approach A (round-reduce Spongent-pi[160] / Dumbo). Three security bands per
# the round-2 spec + addendum:
#   - Hard   (2^60-2^80): nRounds = 32  (linear / rebound key recovery)
#   - Medium (2^40-2^60): nRounds = 24  (linear key recovery)
#   - Easy   (2^30-2^40): nRounds = 18  (linear / differential key recovery)
#
# Spongent's per-round constants are LFSR-derived (lCounter), so any R <= 127
# compiles cleanly. The weakening is applied at GENERATION time: spongent.c
# ships only inside elephant.zip, so we unzip the variant's archive, apply the
# band patch, and repack into the SAME archive name. build_cli.sh stays
# byte-identical to the base. Patch artifacts live in ./variant_patches/ at the
# algorithm ROOT (a sibling of environment/) so they never enter the Docker
# build context and are invisible to the agent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="elephant.zip"
EXTRACT_ROOT="elephant"   # top-level dir inside the archive; patch -p1 -d resolves against it

# band|round-count|patch-file
A_VARIANTS=(
    "easy|18|variant_easy.patch"
    "medium|24|variant_medium.patch"
    "hard|32|variant_hard.patch"
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
