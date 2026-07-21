#!/bin/bash
# Scale-down variant generator for Post-quantum RSA (pqrsa15 KEM), per
# algorithm_scaling_down/nist_pqc/post_quantum_rsa_encryption.txt.
#
# Approach: collapse the many-prime modulus N = p_0*...*p_{K-1} to ordinary
# balanced two-prime RSA (K=2) and shrink the per-prime byte width PBYTES so the
# modulus bit-length N = 16*PBYTES becomes GNFS-factorable:
#   Easy   K=2 PBYTES=24 -> N=384-bit (RSA-384, ~2^30-2^40)
#   Medium K=2 PBYTES=32 -> N=512-bit (RSA-512, ~2^50)
#   Hard   K=2 PBYTES=48 -> N=768-bit (RSA-768, ~2^67)
#
# The patcher (./variant_patches/patch_pqrsa.py) edits the shipped headers
# (internal.h K/PBYTES + the dependent size macros in crypto_kem_pqrsa15.h and
# api.h, kept consistent so dec.c's `#if` static asserts pass). Patch artifacts
# live at the algorithm ROOT (sibling of environment/), so they never enter the
# Docker build context. The weakened source is repacked into the SAME archive
# name so build_cli.sh stays pristine; the committed original archive is never
# touched (we only repack inside each VARIANT_DIR copy).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="PostQuantum_RSA_Enc.zip"
EXTRACT_ROOT="PostQuantum_RSA"
PQRSA_DIR="Reference_Implementation/kem/pqrsa15"

# band|folder-encoding|PBYTES (K is forced to 2 by the patcher)
VARIANTS=(
  "easy|n384|24"
  "medium|n512|32"
  "hard|n768|48"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PBYTES <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_pqrsa.py" \
          "$TMP/$EXTRACT_ROOT/$PQRSA_DIR" "$PBYTES"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
