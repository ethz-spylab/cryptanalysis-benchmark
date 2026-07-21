#!/bin/bash
# Approach A (reduce NTRU_N, the ring degree) per
#   algorithm_scaling_down/nist_pqc/ntru_hrss_kem.txt
#     Hard NTRU_N=389   Medium NTRU_N=269   Easy NTRU_N=197   (shipped full strength 701)
#
# NTRU-HRSS-KEM is an NTRU lattice KEM; security rests on approximate-SVP over the
# 2N-dimensional NTRU lattice, so the single primary knob is the ring degree N.
# q = 2^13 = 8192 (NTRU_LOGQ=13) is kept fixed — lowering N only widens the
# decryption-correctness margin, and the q-width packing routines stay valid.
# N MUST stay prime (HRSS needs x^N-1 = (x-1)*Phi_N with Phi_N irreducible mod 2/3);
# 389, 269, 197 are all prime. All key/ciphertext/packing sizes derive from NTRU_N.
#
# The Python patcher lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/, so it is outside the Docker build context => invisible to the agent).
# The weakened source is repacked into the SAME archive name so build_cli.sh stays
# pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="NTRU_HRSS_KEM.zip"
EXTRACT_ROOT="NIST-PQ-Submission-NTRU-HRSS-KEM-20171130"
# params.h that build_cli.sh actually copies (Reference_Implementation set).
REF_REL="$EXTRACT_ROOT/Reference_Implementation/crypto_kem/ntruhrss701"
PATCHER="$SCRIPT_DIR/variant_patches/patch_ntru_hrss_kem.py"

# band|folder-encoding|NTRU_N value
# (medium drops the band/encoding separating '_' to keep char 32 of the folder
#  name non-underscore: Harbor truncates trial names to 32 chars then joins '__'.)
VARIANTS=(
  "easy|easy_n197|197"
  "medium|mediumn269|269"
  "hard|hard_n389|389"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC NVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$PATCHER" "$TMP/$REF_REL" "$NVAL"

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
  echo "Generated $VARIANT_DIR (NTRU_N=$NVAL, band=$BAND)"
done
