#!/bin/bash
# Approach A (reduce extension degree PARAM_M) per algorithm_scaling_down/nist_pqc/locker.txt
#   Hard   PARAM_M=53 GF2MBYTES=7 PARAM_R=5   (m53r5)
#   Medium PARAM_M=43 GF2MBYTES=6 PARAM_R=5   (m43r5)
#   Easy   PARAM_M=43 GF2MBYTES=6 PARAM_R=4   (m43r4)
# GF2MBYTES=ceil(m/8) is the forced co-edit; the field is auto-built from m
# (BuildSparseIrred_GF2X), so no new modulus is needed. PARAM_N=83, PARAM_D=7
# and MODCOEFFS stay fixed. The Easy band additionally drops PARAM_R to 4
# because m cannot fall far enough at r=5 without violating r*d <= m.
#
# REQUIRED extra co-edit (not in the proposal): src/api.h hardcodes
# CRYPTO_{PUBLICKEY,CIPHERTEXT,SECRETKEY}BYTES = {83*gf, 83*gf+128, 83*gf+40}
# for the base gf=9. When GF2MBYTES shrinks, the serialized key/ciphertext sizes
# shrink too, but these fixed buffers stay oversized, leaving an uninitialised
# tail that the IND-CCA (FO) re-encryption hash diverges on -> 0% round-trip
# unless api.h tracks GF2MBYTES. Each band patch therefore also rewrites api.h.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# Weakened source is repacked into the same archive name so build_cli.sh stays
# pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LOCKER.zip"
# The archive has no single top-level dir; the patched file lives at
# Reference_Implementation/LOCKER-I/src/parameters.h relative to the extract
# root, and the patch paths (a/Reference_Implementation/...) resolve with
# `patch -p1 -d "$TMP"`.
EXTRACT_ROOT="."

# band|param-encoding|patch-file
VARIANTS=(
  "easy|m43r4|variant_easy.patch"
  "medium|m43r5|variant_medium.patch"
  "hard|m53r5|variant_hard.patch"
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
  patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
