#!/bin/bash
# Approach A (reduce the Goppa-code parameters SYS_N / SYS_T) per
#   algorithm_scaling_down/nist_pqc/classic_mceliece.txt
#   Hard   SYS_N=1280 SYS_T=22  (k=1016)  ~2^60-2^80
#   Medium SYS_N=768  SYS_T=16  (k=576)   ~2^40-2^60
#   Easy   SYS_N=512  SYS_T=12  (k=368)   ~2^30-2^40
# GFBITS stays 12 (GF(2^12) field arithmetic + Benes network unchanged), so only
# SYS_N / SYS_T move; api.h and the namespaced header hard-code the KEM byte
# sizes, so the patcher recomputes those too (every compiled .c file already
# derives its buffers from the params.h macros).
#
# Patch artifact in ./variant_patches/ lives at the algorithm ROOT (a sibling of
# environment/), so it is OUTSIDE the Docker build context => invisible to the
# agent. The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine. The unrelated build-compat helper
# environment/algorithm_src/patch_mceliece.py is left untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="mceliece-20221023.tar.gz"
EXTRACT_ROOT="mceliece-20221023"
REF_REL="Reference_Implementation/kem/mceliece348864"
PATCHER="$SCRIPT_DIR/variant_patches/patch_mceliece_variant.py"

# band|param-encoding|SYS_N|SYS_T
VARIANTS=(
  "easy|n512t12|512|12"
  "medium|n768t16|768|16"
  "hard|n1280t22|1280|22"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC SYS_N SYS_T <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  tar xzf "$ARCH" -C "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$REF_REL" "$SYS_N" "$SYS_T"
  ( cd "$TMP" && rm -f "$ARCH" && tar czf "$ARCH" "$EXTRACT_ROOT" )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
