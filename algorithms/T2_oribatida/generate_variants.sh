#!/bin/bash
# Approach A (reduce inner Simon round count R per SimP step) per
# algorithm_scaling_down/nist_lwc/oribatida.txt
#   Hard R=7  Medium R=5  Easy R=3   (full strength is R=26)
#
# The knob is the single loop bound in SimP_round() inside SimP_192.h:
#   for(i = 0; i < 26; i++)  ->  for(i = 0; i < R; i++)
# SimP_4 = 4 steps x R Simon rounds drives the whole AEAD's differential
# resistance. The `26 * round` z-index stride is deliberately left intact.
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened SimP_192.h is repacked into the SAME oribatida.zip name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="oribatida.zip"
EXTRACT_ROOT="oribatida"
TARGET_REL="Implementations/crypto_aead/oribatida192v12/ref/SimP_192.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_oribatida.py"

# band|R
VARIANTS=(
  "easy|3"
  "medium|5"
  "hard|7"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND R <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_r${R}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$R"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
