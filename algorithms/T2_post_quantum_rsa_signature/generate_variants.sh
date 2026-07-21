#!/bin/bash
# Approach: reduce the RSA modulus N to a factorable two-prime RSA, per
# algorithm_scaling_down/nist_pqc/post_quantum_rsa_signature.txt
#   Hard   K=2 PBYTES=48 -> N=768-bit (RSA-768, ~2^67)
#   Medium K=2 PBYTES=32 -> N=512-bit (RSA-512, ~2^50)
#   Easy   K=2 PBYTES=24 -> N=384-bit (RSA-384, ~2^30-2^40)
#
# The knob lives in internal.h (K, PBYTES); the dependent size macros in
# crypto_sign_pqrsa15.h (SECRETKEYBYTES=3*K*PBYTES, PUBLICKEYBYTES=K*PBYTES,
# BYTES=32+K*PBYTES) and api.h must stay consistent or the #if static asserts
# in sign.c fail the build. All three headers ship inside the vendored archive,
# so each band's patch edits all of them.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# Weakened source is repacked into the same archive name so build_cli.sh stays
# pristine. The committed original archive is NEVER modified.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="PostQuantum_RSA_Sign.zip"
EXTRACT_ROOT="PostQuantum_RSA_Sign"   # top-level dir inside the archive

# band|param-encoding|patch-file
VARIANTS=(
  "easy|k2p24|variant_easy.patch"
  "medium|k2p32|variant_medium.patch"
  "hard|k2p48|variant_hard.patch"
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
  # patch paths are a/PostQuantum_RSA_Sign/... ; -p1 strips a/, resolved at $TMP
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" "$EXTRACT_ROOT" )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
