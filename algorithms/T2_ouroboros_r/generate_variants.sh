#!/bin/bash
# Approach: reduce the extension degree m (PARAM_M / FIELD_M) per
# algorithm_scaling_down/nist_pqc/ouroboros_r.txt
#   Hard m=83   Medium m=61   Easy m=43   (shipped real algorithm: m=89, never emitted)
#
# m lives in TWO synchronized macros that must stay equal:
#   src/parameters.h      #define PARAM_M <m>   (sizes/logic)
#   src/ffi/ffi.h         #define FIELD_M <m>   (GF(2^m) field construction)
# n=53, w=5, w_r=6 stay fixed so the LRPC decoding bound (w*w_r=30 <= n=53) holds.
# NTL's BuildSparseIrred_GF2X(FIELD_M) regenerates the field polynomial, so no new
# modulus is needed.
#
# DEVIATION FROM PROPOSAL: a THIRD macro must also be patched.
#   src/ffi/ffi.h         #define FIELD_ELT_BYTES <ceil(m/8)>
# FIELD_ELT_BYTES is the per-element byte STRIDE used by ffi_vec serialization
# (ffi_elt_to_string -> BytesFromGF2X(.., FIELD_ELT_BYTES)), while the vector layout
# offsets (FFI_VEC_N_BYTES / FFI_VEC_R_BYTES = PARAM_x*(PARAM_M/8+1)) use PARAM_M/8+1.
# The two only coincide at m=89 (both 12). Leaving FIELD_ELT_BYTES=12 for smaller m
# overflows the support[FFI_VEC_R_BYTES] stack buffer in kem.cpp (stack-smashing for
# m=43/61) and misaligns the ciphertext sr/se split (100% decode failure at m=83).
# Setting FIELD_ELT_BYTES = PARAM_M/8+1 = ceil(m/8) restores stride==offset and loses
# no field bits (a GF(2^m) element needs exactly ceil(m/8) bytes). The hardcoded
# api.h CRYPTO_*BYTES (sized for m=89) stay larger than needed and are harmless padding
# that the *_from_string parsers ignore.
#
# The patch artifact in ./variant_patches/ lives at the algorithm ROOT (a sibling of
# environment/), so it never enters the Docker build context and is invisible to the
# agent. Weakened source is repacked into the same archive name so build_cli.sh stays
# pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Ouroboros_R.zip"
# The ouroboros-r-128 set that build_cli.sh compiles.
SET_DIR="Reference_Implementation/ouroboros-r-128"
PARAMS_H="$SET_DIR/src/parameters.h"
FFI_H="$SET_DIR/src/ffi/ffi.h"

# band|m-value
VARIANTS=(
  "easy|43"
  "medium|61"
  "hard|83"
)
for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND M <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_m${M}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"
  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  ELT_BYTES=$(( M / 8 + 1 ))   # ceil(m/8) for m not divisible by 8 (43,61,83 all qualify)
  python3 "$SCRIPT_DIR/variant_patches/patch_ouroboros_r.py" "$TMP/$PARAMS_H" PARAM_M "$M"
  python3 "$SCRIPT_DIR/variant_patches/patch_ouroboros_r.py" "$TMP/$FFI_H"    FIELD_M "$M"
  python3 "$SCRIPT_DIR/variant_patches/patch_ouroboros_r.py" "$TMP/$FFI_H"    FIELD_ELT_BYTES "$ELT_BYTES"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
