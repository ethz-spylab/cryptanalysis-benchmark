#!/bin/bash
# Approach A (reduce SKINNY-128-128 round count) per algorithm_scaling_down/nist_lwc/remus.txt
#   File:  remus/Implementations/crypto_aead/remusn1v1/ref/skinny_reference.c
#   Const: versions[3] = {128,128,40}  (round count is the 3rd field)
#   Easy R=10   Medium R=13   Hard R=16   (shipped full strength R=40 is never emitted)
#
# Patch artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they never enter the Docker build context and stay invisible to the
# agent. The weakened skinny_reference.c is repacked into the same remus.zip archive name
# so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="remus.zip"
EXTRACT_ROOT="remus"   # top-level dir inside remus.zip

# band|param-encoding|patch-file
VARIANTS=(
  "easy|r10|variant_easy.patch"
  "medium|r13|variant_medium.patch"
  "hard|r16|variant_hard.patch"
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
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
