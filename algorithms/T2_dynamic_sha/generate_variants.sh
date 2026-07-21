#!/bin/bash
# Round-reduced variant generator for T2_dynamic_sha (NIST SHA-3 Round 1, Dynamic SHA).
#
# Approach A (reduce compression round count) on dsha_ref.h:
#   full strength = 48 rounds (both sha32_compile and sha64_compile)
#   Hard rounds=24   Medium rounds=16   Easy rounds=8
#
# The weakening is applied at GENERATION time and repacked into the SAME archive
# name (DyamicSHA.zip) so build_cli.sh stays byte-identical (pristine). The patch
# artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they never enter the Docker build context and the agent never
# sees them; the variant's copy of variant_patches/ is deleted after repacking.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="DyamicSHA.zip"
# Path INSIDE the archive (note the literal space in the directory name).
HEADER_REL="DynamicSHA/Reference Implementation/dsha_ref.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_dynamic_sha.py"

# band|folder-encoding|rounds
VARIANTS=(
  "easy|r8|8"
  "medium|r16|16"
  "hard|r24|24"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC ROUNDS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$PATCHER" "$TMP/$HEADER_REL" "$ROUNDS"

  # Repack into the SAME archive name, preserving the internal layout
  # (top-level DynamicSHA/ dir) that build_cli.sh expects.
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Remove the patch artifacts from the shipped variant (concealment).
  rm -rf "$VARIANT_DIR/variant_patches"

  echo "Generated variant: $VARIANT_DIR (rounds=$ROUNDS)"
done
