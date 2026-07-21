#!/bin/bash
# Approach A (reduce CRYPTO_n, the LWE dimension n) per
#   algorithm_scaling_down/nist_pqc/emblem_and_r_emblem.txt
#   Hard CRYPTO_n=330  Medium CRYPTO_n=240  Easy CRYPTO_n=165   (real value 611)
#
# The benchmark compiles the EMBLEM KEM from EMBLEM_R_EMBLEM/KAT/EMBLEM. The LWE
# dimension n lives in kem.c (#define CRYPTO_n). Because the serialized key /
# ciphertext byte sizes are derived from n (PUBLICKEYBYTES = 4*m*(n+1),
# SECRETKEYBYTES = 4*n + PUBLICKEYBYTES, CIPHERTEXTBYTES = 4*(v*(n+k)+8)), each
# band patch ALSO recomputes the three matching #defines in api.h so that the
# buffers in cli.c / kem.c stay correctly sized (per the proposal's caveat).
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enter the Docker build context => invisible to the agent).
# Weakened source is repacked into the SAME archive name so build_cli.sh stays
# pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="EMBLEM_R_EMBLEM.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|n165|variant_easy.patch"
  "medium|n240|variant_medium.patch"
  "hard|n330|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PATCH <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"           # -> $TMP/EMBLEM_R_EMBLEM/...
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
