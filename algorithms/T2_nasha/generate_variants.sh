#!/bin/bash
# Approach A (reduce the LinTr256^16 MT application count) per
# algorithm_scaling_down/nist_sha3/nasha.txt
#   Knob: NaSHA/ReferenceImplementation/Nasha.c, LinTr16 loop bound
#         `for (j=1;j<=16;j++)`  (real 16)
#   Hard  j<=8    Medium  j<=5    Easy  j<=3
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name
# (NaSHAUpdate.zip) so environment/algorithm_src/build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="NaSHAUpdate.zip"
EXTRACT_ROOT="NaSHA"   # top-level dir inside the archive; patch -d resolves here

# band|param-encoding|patch-file
VARIANTS=(
  "easy|lt3|variant_easy.patch"
  "medium|lt5|variant_medium.patch"
  "hard|lt8|variant_hard.patch"
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
