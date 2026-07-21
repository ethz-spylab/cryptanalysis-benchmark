#!/bin/bash
# Approach: reduce the applied Xoodoo round count per
#   algorithm_scaling_down/nist_lwc/xoodyak.txt
#   Hard N=8   Medium N=6   Easy N=5   (full strength = 12, never emitted)
#
# The knob is the body of Xoodoo_Permute_12rounds() in
#   xoodyak/Implementations/crypto_aead/xoodyakround3/ref/Xoodoo-reference.c
# which is changed from Xoodoo_Permute_Nrounds(state, 12) to (state, N).
# Xoodoo_Permute_Nrounds selects the LAST N round constants
# (for i = MAXROUNDS - nr ...), so reduced-round constants stay correct and
# no RC-table / MAXROUNDS edit is needed.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/) so they never enter the Docker build context and are invisible
# to the agent. The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="xoodyak.zip"
EXTRACT_ROOT="xoodyak"   # top-level dir inside the archive

# band|param-encoding|patch-file
VARIANTS=(
  "easy|r5|variant_easy.patch"
  "medium|r6|variant_medium.patch"
  "hard|r8|variant_hard.patch"
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
