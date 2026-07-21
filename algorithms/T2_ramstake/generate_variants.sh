#!/bin/bash
# Scaling-down variants for Ramstake RS 216091 (NIST PQC Round 1, KEM).
# Approach: reduce the secret Hamming weight w (both masses) per
#   algorithm_scaling_down/nist_pqc/ramstake.txt
#     Hard   w=8  (MITM C(216091,4) ~ 2^66)
#     Medium w=6  (MITM C(216091,3) ~ 2^51)
#     Easy   w=4  (MITM C(216091,2) ~ 2^34)
# The Mersenne prime exponent RAMSTAKE_MODULUS_BITSIZE = 216091 is left
# untouched (keeps the genuine Mersenne prime and a large lattice dimension).
#
# Patch artifact in ./variant_patches/ lives at the algorithm ROOT (sibling of
# environment/), so it never enters the Docker build context and stays invisible
# to the agent. The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Ramstake.zip"
EXTRACT_ROOT="ramstake"   # top-level dir inside Ramstake.zip
TARGET_REL="Reference_Implementation/Ramstake_RS_216091/ramstake.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_ramstake.py"

# band|w-encoding|mass-value
VARIANTS=(
  "easy|w4|4"
  "medium|w6|6"
  "hard|w8|8"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC WVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$WVAL"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
  echo "Generated $VARIANT_DIR (w=$WVAL)"
done
