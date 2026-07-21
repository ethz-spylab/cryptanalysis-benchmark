#!/bin/bash
# Approach A (reduce Feistel round count) per algorithm_scaling_down/nist_sha3/simd.txt
#   SIMD_Compress() in SIMD/Reference_Implementation/reference.c applies four
#   Feistel Round() calls (i=0..3) before a 4-step Davies-Meyer feed-forward.
#   The round count is the primary security knob. Each band deletes trailing
#   Round() calls while keeping the feed-forward intact:
#     Hard   ROUNDS=3  (keep Round i=0,1,2)
#     Medium ROUNDS=2  (keep Round i=0,1)
#     Easy   ROUNDS=1  (keep Round i=0)
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same simd.zip name so build_cli.sh
# stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="simd.zip"
EXTRACT_ROOT="SIMD"   # top-level dir inside the archive; patch -d resolves here

# band|param-encoding|patch-file
VARIANTS=(
  "easy|r1|variant_easy.patch"
  "medium|r2|variant_medium.patch"
  "hard|r3|variant_hard.patch"
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
