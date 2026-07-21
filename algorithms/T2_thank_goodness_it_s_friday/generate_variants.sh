#!/bin/bash
# Approach A (reduce TGIF-BC round count `total_step`) per
# algorithm_scaling_down/nist_lwc/thank_goodness_it_s_friday.txt
#   Full=18  Hard total_step=9  Medium total_step=6  Easy total_step=4
# (each Feistel step = 4 internal GIFT rounds; left_rotation=55 unchanged.)
#
# The knob is the single line `int total_step=18;` inside TGIF_BC() in
#   tgif/Implementations/crypto_aead/tgifn1128v1/ref/TGIF_BC.c
# which build_cli.sh copies verbatim out of tgif.zip before compiling.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent. The weakened source is repacked into the same archive name
# (tgif.zip) so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="tgif.zip"
EXTRACT_ROOT="tgif"   # top-level dir inside the archive; patch -d resolves here

# band|param-encoding|patch-file
VARIANTS=(
  "easy|ts4|variant_easy.patch"
  "medium|ts6|variant_medium.patch"
  "hard|ts9|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PATCH <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"
  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
