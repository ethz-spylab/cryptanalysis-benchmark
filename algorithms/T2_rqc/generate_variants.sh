#!/bin/bash
# Scaling-down variants for RQC (rank quasi-cyclic, code-based KEM) per
# algorithm_scaling_down/nist_pqc/rqc.txt — Approach: reduce the extension
# degree m (primary), co-reducing the code length n, dimension k, and rank
# weights w / w_r so that the Gabidulin constraint n<=m and the decryption
# constraint w*w_r <= floor((n-k)/2) keep holding. Both m and n stay PRIME.
#
#   Baseline (as-shipped rqc128, hardest, NOT a variant): m=97 n=67 k=4 w=5 w_r=6  (~2^77 real)
#   Hard   m=53 n=41 k=3 w=4 w_r=4   (~2^60-2^68)   ideal-modulo X^41+X^3+1
#   Medium m=37 n=23 k=3 w=3 w_r=3   (~2^40-2^60)   ideal-modulo X^23+X^5+1
#   Easy   m=23 n=17 k=3 w=2 w_r=3   (~2^30-2^40)   ideal-modulo X^17+X^3+1
#
# Each patch edits THREE headers in the Reference_Implementation/rqc128 tree:
#   src/parameters.h  (PARAM_M/N/K/W/W_R + derived VEC_*/FFI_ELT_BYTES)
#   src/api.h         (CRYPTO_SECRETKEYBYTES/PUBLICKEYBYTES/CIPHERTEXTBYTES)
#   src/ffi/ffi.h     (FIELD_M, FIELD_ELT_BYTES, and the degree-n ideal-modulo
#                      polynomial MODULO_NUMBER/MODULO_VALUES)
# The field polynomial of degree m is auto-built by NTL (BuildSparseIrred), so
# only the ideal modulo (degree n) is supplied explicitly; each is an
# irreducible polynomial of degree n.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => outside the Docker build context => invisible to the agent).
# The weakened source is repacked into the SAME archive name inside the variant
# copy, so build_cli.sh and the committed original archive stay pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="RQC-Round2.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|m23n17|variant_easy.patch"
  "medium|m37n23|variant_medium.patch"
  "hard|m53n41|variant_hard.patch"
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
  # Patch paths are a/RQC/... and b/RQC/... ; -p1 strips the a/ or b/ leading
  # component and resolves RQC/... against $TMP (where the tree was extracted).
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Never ship the patch artifacts inside a task (concealment).
  rm -rf "$VARIANT_DIR/variant_patches"
done
