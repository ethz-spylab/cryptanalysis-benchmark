#!/bin/bash
# Approach: reduce the number of Mini-Rounds in Twister's compression function
# twist() (the <=256-bit branch used by the default --hashbitlen 256), per
# algorithm_scaling_down/nist_sha3/twister.txt.
#
# Full strength = 3 Maxi-Rounds = 9 Mini-Rounds per 512-bit block. We trim whole
# Maxi-Rounds (feed-forward groups) / message injections:
#   Hard   : 2 Maxi-Rounds  -> 6 Mini-Rounds  (msg[0..5])
#   Medium : 1 Maxi-Round   -> 3 Mini-Rounds  (msg[0..2])
#   Easy   : 1 Maxi-Round, 2 mini -> 2 Mini-Rounds (msg[0..1])
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/, so they never enter the Docker build context => invisible to the
# agent). The weakened ref_twister.cpp is repacked into the same twister.zip name
# so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="twister.zip"
EXTRACT_ROOT="Twister"   # top-level dir inside the archive; patch -d resolves here

# band|param-encoding (mini-round count)|patch-file
VARIANTS=(
  "easy|r2|variant_easy.patch"
  "medium|r3|variant_medium.patch"
  "hard|r6|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PATCH <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
  # Repack into the SAME archive name with the SAME internal layout.
  rm -f "$ARCH"
  ( cd "$TMP" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Remove the patch artifacts from the variant so they never ship.
  rm -rf "$VARIANT_DIR/variant_patches"

  echo "Generated $VARIANT_DIR (mini-rounds=${ENC#r})"
done
