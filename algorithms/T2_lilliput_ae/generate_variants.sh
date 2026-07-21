#!/bin/bash
# Round-reduced variants of Lilliput-AE (lilliputaeii128v1, AEAD).
#
# Knob: Lilliput-TBC round count
#   lilliput-ae/Implementations/crypto_aead/lilliputaeii128v1/ref/parameters.h
#   #define ROUNDS  (full strength = 32)
# This single #define drives both the round loop and the tweakey schedule
# (the RTK table is sized [ROUNDS] and every loop is bounded by ROUNDS), so
# reducing it weakens the cipher while keeping encrypt/decrypt round-trip
# consistent. Each band is strictly weaker than the shipped full=32 task.
#   Hard   ROUNDS = 20
#   Medium ROUNDS = 14
#   Easy   ROUNDS = 8
#
# Patch files live in ./variant_patches/ (algorithm ROOT, outside environment/
# => never enters the Docker build context => invisible to the agent). The
# weakened source is repacked into the vendored archive (same name) so
# build_cli.sh stays pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"        # algorithm root
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="lilliput-ae.zip"
EXTRACT_ROOT="lilliput-ae"                          # top-level dir inside the archive

# band|param-encoding|patch-file
VARIANTS=(
    "easy|r8|variant_easy.patch"
    "medium|r14|variant_medium.patch"
    "hard|r20|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f  "$VARIANT_DIR/generate_variants.sh"

    # Apply the weakening to the extracted source, then repack into the SAME
    # archive name so build_cli.sh's unzip step is unchanged.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # The patch artifacts sit at the variant root (outside environment/), so
    # they never enter the image; remove them to keep the task folder clean.
    rm -rf "$VARIANT_DIR/variant_patches"
done
