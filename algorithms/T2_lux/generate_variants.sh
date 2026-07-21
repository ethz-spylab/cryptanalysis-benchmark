#!/bin/bash
# Approach A (reduce the blank-round count in Final()) per
# algorithm_scaling_down/nist_sha3/lux.txt
#   Hard LUX_BLANK_ROUNDS=8  Medium LUX_BLANK_ROUNDS=4  Easy LUX_BLANK_ROUNDS=2
# (shipped full-strength value is 16; never emitted as a variant).
#
# The knob is the literal "16" in the loop
#   for(i=0;i<16;i++){ compressLUX(state,empty); }
# inside Final() in LUX-CD/Reference_Implementation/LUX.c.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same LUX.zip archive name so
# build_cli.sh stays pristine. The committed original archive is never touched
# (we only ever extract/repack inside $VARIANT_DIR).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LUX.zip"
EXTRACT_ROOT="LUX-CD"   # the top-level dir inside LUX.zip; patch -p1 -d resolves against it

# band|param-encoding|patch-file
VARIANTS=(
  "easy|br2|variant_easy.patch"
  "medium|br4|variant_medium.patch"
  "hard|br8|variant_hard.patch"
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
