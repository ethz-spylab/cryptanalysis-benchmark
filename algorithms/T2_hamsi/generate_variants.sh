#!/bin/bash
# Approach (reduce permutation round counts) per algorithm_scaling_down/nist_sha3/hamsi.txt
#   File/const: Hamsi/Reference_Implementation/nist-wrapper.c (Init):
#     state->ROUNDS = 3*size;  state->PFROUNDS = 6*size;
#   Real (size=1, --hashbitlen 256): ROUNDS=3, PFROUNDS=6
#     Hard   ROUNDS=2 PFROUNDS=3
#     Medium ROUNDS=1 PFROUNDS=2
#     Easy   ROUNDS=1 PFROUNDS=1
#   Both counts are scaled by `size` so the 512-bit member mirrors the reduction.
# Patch artifacts in ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent). Weakened source is repacked into the same
# archive name (hamsi.zip) so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="hamsi.zip"
EXTRACT_ROOT="Hamsi"   # top-level dir inside the archive; patch -p1 resolves against it

# band|param-encoding|patch-file
VARIANTS=(
  "easy|r1pf1|variant_easy.patch"
  "medium|r1pf2|variant_medium.patch"
  "hard|r2pf3|variant_hard.patch"
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
