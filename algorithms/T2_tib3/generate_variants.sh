#!/bin/bash
# Approach A (reduce block-permutation round count) per
# algorithm_scaling_down/nist_sha3/tib3.txt
#   File/constant: TIB3/Reference_Implementation/encrypt256.c — the ROUND()
#   calls inside #define FOURROUNDSBOX (~line 87). Full strength runs 4 ROUNDs
#   per group across all four INPUT* groups = 16 rounds total. We delete
#   trailing ROUND() lines so every group runs fewer rounds:
#     Hard   3 ROUND/group = 12 rounds total
#     Medium 2 ROUND/group =  8 rounds total
#     Easy   1 ROUND/group =  4 rounds total
# All four message-injection groups (INPUTONE..FOUR) are kept intact, so the
# full message block + previous block are still absorbed; only the diffusion
# between injections is shortened.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never part of the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name (tib3.zip)
# so build_cli.sh stays pristine. The committed original archive under
# $SCRIPT_DIR is never modified — only the per-variant copy is.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="tib3.zip"
EXTRACT_ROOT="TIB3"   # top-level dir inside tib3.zip; patch -d resolves against it

# band|param-encoding (total rounds)|patch-file
VARIANTS=(
  "easy|r4|variant_easy.patch"
  "medium|r8|variant_medium.patch"
  "hard|r12|variant_hard.patch"
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
