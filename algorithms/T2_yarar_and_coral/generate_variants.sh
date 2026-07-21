#!/bin/bash
# Approach A (reduce ROUNDS) per algorithm_scaling_down/nist_lwc/yarar_and_coral.txt
#   Scheme: Yarara-128 AEAD (yarara128v1). Knob: data-path permutation round count
#   #define ROUNDS in Implementations/crypto_aead/yarara128v1/ref/encrypt.c
#   (FINAL_ROUNDS follows automatically; INITIAL_ROUNDS=10 left intact).
#   Full strength ROUNDS=6 ->  Hard ROUNDS=4   Medium ROUNDS=3   Easy ROUNDS=2
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside environment/
# => never in the Docker build context => invisible to the agent). The weakened
# source is repacked into the same archive name so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="yarara-coral.zip"

# band|param-encoding|patch-file
# encoding has no leading underscore: the long algo name pushes the band/enc
# separator to char 32 for the short "easy" band (Harbor 32-char trial-name
# gotcha => would truncate to a trailing '_'), so band+enc are joined directly.
VARIANTS=(
  "easy|r2|variant_easy.patch"
  "medium|r3|variant_medium.patch"
  "hard|r4|variant_hard.patch"
)
for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PATCH <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"
  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  # patch paths are a/yarara-coral/... ; -p1 strips a/ leaving yarara-coral/...
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
