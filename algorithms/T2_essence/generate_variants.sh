#!/bin/bash
# Approach A (reduce ESSENCE_COMPRESS_NUM_STEPS) per algorithm_scaling_down/nist_sha3/essence.txt
#   Hard ESSENCE_COMPRESS_NUM_STEPS=30  Medium =24  Easy =16  (shipped full strength = 32)
#
# The single security parameter is the compression step count in
#   ESSENCE/CD - UNIX EOL/Reference_Implementation/essence_api.h
#       #define ESSENCE_COMPRESS_NUM_STEPS 32
# build_cli.sh copies that header out of the unzipped tree before compiling, so
# weakening it inside the repacked ESSENCE.zip propagates to the built cli with
# no change to build_cli.sh. The macro also re-keys the MD IV, so no other
# source file is sized by the step count.
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same archive name so build_cli.sh
# stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="ESSENCE.zip"
EXTRACT_ROOT="ESSENCE"   # top-level dir inside the archive
TARGET_REL="CD - UNIX EOL/Reference_Implementation/essence_api.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_essence.py"

# band|param-encoding|num_steps
VARIANTS=(
  "easy|s16|16"
  "medium|s24|24"
  "hard|s30|30"
)
for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC VAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$VAL"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
