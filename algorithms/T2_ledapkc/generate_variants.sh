#!/bin/bash
# Approach: reduce the circulant block size P together with the error weight
# NUM_ERRORS_T (t) and the constant-weight-encoder capacity
# MAX_ENCODABLE_BIT_SIZE_CW_ENCODING, per
# algorithm_scaling_down/nist_pqc/ledapkc.txt.
#
# Edited constants live in the CATEGORY==1 / N0==2 block of
#   Reference_Implementation/LEDApkc/include/qc_ldpc_parameters.h
# (DV held at 17; K, N, DC derive automatically from P).
#
#   Hard   P=15859 t=128 MAX_ENCODABLE=1150
#   Medium P=10909 t=88  MAX_ENCODABLE=790
#   Easy   P=7907  t=64  MAX_ENCODABLE=573
#
# P must be prime with 2 a primitive root mod P (so x^P-1 = (x-1)*irreducible,
# keeping the circulant ring a field). The proposal's medium (10903) and easy
# (7919) values are prime but do NOT have ord_2 = P-1, so the nearest qualifying
# primes are substituted: 10903->10909 (+6), 7919->7907 (-12). Hard (15859)
# already qualifies. MAX_ENCODABLE is recomputed conservatively below the
# information-theoretic CW capacity log2(C(2P,t)) at each band.
#
# Patch artifacts in ./variant_patches/ (algorithm ROOT, outside environment/
# => never in the Docker build context => invisible to the agent). Weakened
# source is repacked into the same archive name so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LEDApkc.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|p7907t64|variant_easy.patch"
  "medium|p10909t88|variant_medium.patch"
  "hard|p15859t128|variant_hard.patch"
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
