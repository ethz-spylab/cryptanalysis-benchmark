#!/bin/bash
# Scaling-down variants for Gui (HFEv- multivariate signature), per
# algorithm_scaling_down/nist_pqc/gui.txt — Approach: reduce the HFE extension
# degree _EXT (= n, the GF(2^n) dimension and the size of the public MQ/MinRank
# instance) in Reference_Implementation/Gui-184/gui_config.h, holding
# D=33, v=16, a=16, k=2 fixed.
#
#   Hard   _EXT=104  (W=13 bytes, ~2^73)
#   Medium _EXT=72   (W=9  bytes, ~2^50)
#   Easy   _EXT=48   (W=6  bytes, ~2^34)
#
# Because the field GF(2^_EXT) is implemented as GF(256)^(_EXT/8) and the stock
# gfext.h only ships hand-written byte-width arithmetic for W in {30,23,39,56},
# each band's patch ALSO adds the missing GF(256)^W field arithmetic (mul/squ/
# inv with a verified degree-W irreducible polynomial over GF(256)) for
# W in {13,9,6}. All other sizes (_PUB_N, _PUB_M, key/signature byte lengths)
# derive from _EXT automatically. _STEP stays 4 (set by the parameter-set macro)
# and _EXT%4==0 for every band, so the root-finding code path is unchanged.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Gui.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|ext48|variant_easy.patch"
  "medium|ext72|variant_medium.patch"
  "hard|ext104|variant_hard.patch"
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
