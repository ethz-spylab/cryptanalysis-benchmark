#!/bin/bash
# Approach A (reduce ROUNDS) per algorithm_scaling_down recipe for CAST-256.
# The reference has no `#define ROUNDS`; the 12 quad-rounds are unrolled inside
# encrypt()/decrypt() in cast.c (6 f_rnd + 6 i_rnd). Bands (out of 48 micro-rounds):
#   Hard   R=16  -- 4 quad-rounds
#   Medium R=14  -- 3 quad-rounds + 2 inline-expanded micro-rounds (half quad-round)
#   Easy   R=12  -- 3 quad-rounds
#
# Concealment: the round-sequence edit lives in committed unified-diff patches under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/, so it never enters the
# Docker build context). At generation time we unzip the variant's copy of CAST-256-2.zip,
# apply the band patch to cast.c, and repack into the SAME archive name. build_cli.sh stays
# byte-identical to base (it still just unzips, CRLF-strips, and compiles).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="CAST-256-2.zip"
# Archive has cast.c / std_defs.h at top level -> patch -p1 resolves against the extract dir.

# band|R|patch-file
VARIANTS=(
    "easy|12|variant_easy.patch"
    "medium|14|variant_medium.patch"
    "hard|16|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}"
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
