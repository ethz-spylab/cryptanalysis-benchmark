#!/bin/bash
# Approach A (reduce the digest size HASH_SIZE) per
#   algorithm_scaling_down/nist_pqc/gravity_sphincs.txt
#   Hard HASH_SIZE=9 (n=72 bits, ~2^72)  Medium HASH_SIZE=6 (n=48, ~2^48)
#   Easy HASH_SIZE=4 (n=32 bits, ~2^32)
#
# HASH_SIZE is not a clean one-liner: the reference hardwires 256-bit Haraka /
# SHA-256 and a 32-byte digest in several spots. variant_patches/patch_gravity_
# sphincs.py applies the minimal coordinated edit set (common.h HASH_SIZE +
# WOTS_ell1, hash.h alignment, the four hash.c wrappers incl. the iterated WOTS+
# chain, the aes.c key zero-extension, and api.h size macros). The patch
# artifact lives at the algorithm ROOT (./variant_patches/), a sibling of
# environment/, so it never enters the Docker build context and stays invisible
# to the agent. The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine. The committed original archive is never modified.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Gravity_SPHINCS.zip"
EXTRACT_ROOT="gravity-sphincs"   # top-level dir inside the archive
REF_REL="$EXTRACT_ROOT/Reference_Implementation"
PATCHER="$SCRIPT_DIR/variant_patches/patch_gravity_sphincs.py"

# band|name-encoding|HASH_SIZE   (no '_' between band and enc: dodges the
# 32-char trial-name truncation landing on a trailing '_')
VARIANTS=(
  "easy|easyhs4|4"
  "medium|mediumhs6|6"
  "hard|hardhs9|9"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC HS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$PATCHER" "$TMP/$REF_REL" "$HS"

  # Repack into the same archive name with the same internal layout
  # (gravity-sphincs/... at top) so build_cli.sh is unaffected.
  rm -f "$ARCH"
  ( cd "$TMP" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # The patch artifacts must not ship inside the task.
  rm -rf "$VARIANT_DIR/variant_patches"

  echo "Generated $VARIANT_DIR (band=$BAND HASH_SIZE=$HS)"
done
