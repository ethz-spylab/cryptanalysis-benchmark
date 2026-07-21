#!/bin/bash
# Approach: reduce the field extension degree m (PARAM_M) of LAKE-I per
# algorithm_scaling_down/nist_pqc/lake.txt.
#   Hard  PARAM_M=61 GF2MBYTES=8  (~2^65, capped below the real m=67 ~2^71)
#   Medium PARAM_M=47 GF2MBYTES=6 (~2^48)
#   Easy  PARAM_M=37 GF2MBYTES=5  (~2^38)
# n, d, r and MODCOEFFS are held fixed so the ideal ring X^47+X^5+1 and the LRPC
# decoder stay valid; the GF(2^m) modulus is auto-built by NTL. The shipped m=67
# set is the (real) baseline and is never emitted as a variant.
#
# Patch artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent. The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LAKE.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|m37|variant_easy.patch"
  "medium|m47|variant_medium.patch"
  "hard|m61|variant_hard.patch"
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
  # Patch paths are a/Reference_Implementation/... so -p1 resolves against $TMP.
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  chmod -R u+w "$TMP"
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
