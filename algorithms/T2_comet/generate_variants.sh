#!/bin/bash
# Approach A (reduce Speck-64/128 ROUNDS) per algorithm_scaling_down/nist_lwc/comet.txt
#   Hard ROUNDS=20  Medium ROUNDS=16  Easy ROUNDS=12   (full strength = 27)
# Knob: comet/Implementations/crypto_aead/comet64speckv1/ref/speck_64-128_and_128-128.c
#   '#define ROUNDS 27' inside the '#if BLOCKSIZE == 64' branch. ROUNDS drives both the
#   Speck key schedule (ROUNDS-1 round keys) and the encryption loop, so one edit scales
#   the whole core. The BLOCKSIZE==128 branch (ROUNDS 32) is dead code (options.h pins
#   BLOCKSIZE 64) and is left untouched.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of environment/,
# so they never enter the Docker build context and stay invisible to the agent). The
# weakened source is repacked into the same comet.zip name so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="comet.zip"
EXTRACT_ROOT="comet"   # top-level dir inside the archive; patch -p1 resolves against this

# band|param-encoding|patch-file
VARIANTS=(
  "easy|r12|variant_easy.patch"
  "medium|r16|variant_medium.patch"
  "hard|r20|variant_hard.patch"
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
