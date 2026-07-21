#!/bin/bash
# Approach A (reduce AES-core round count) per algorithm_scaling_down/nist_sha3/lesamnta.txt
#   Knob: lesamnta_refer.c  #define Nr_comp256 / #define Nr_out256  (real 32)
#   Hard Nr=12   Medium Nr=8   Easy Nr=6   (compression and output rounds kept equal)
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of environment/ =>
# never enter the Docker build context => invisible to the agent). The weakened source is
# repacked into the same archive name so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Lesamnta.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|r6|variant_easy.patch"
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
  # Patch paths are 'a/Nist_submission_Lesamnta_October2008/...'; -p1 strips the 'a/' prefix
  # and resolves against $TMP (which holds the extracted top-level dir).
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
