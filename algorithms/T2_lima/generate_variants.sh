#!/bin/bash
# Scale-down variants for LIMA-sp (Ring-LWE KEM) per
# algorithm_scaling_down/nist_pqc/lima.txt — Approach: reduce ring dimension N
# (the 3rd field of the lima_sp_1018 struct in Lib/lima.c) together with a
# matched NTT-friendly prime modulus q and the four primitive-root seeds
# alpha0/alpha1/beta0/beta1 (regenerated, NOT copied — they are (N,q)-specific).
#
#   Easy   N=262 (p=263 safe prime, q=9695233 )  -> core-SVP ~2^34
#   Medium N=382 (p=383 safe prime, q=12942337)  -> core-SVP ~2^50
#   Hard   N=502 (p=503 safe prime, q=10816513)  -> core-SVP ~2^66
#
# All edits are applied by variant_patches/patch_lima.py against the freshly
# unzipped upstream tree, then the weakened source is repacked into the SAME
# archive name (Lima.zip) so build_cli.sh stays pristine.  The patch artifacts
# live at the algorithm ROOT (./variant_patches), a sibling of environment/, so
# they never enter the Docker build context and are invisible to the agent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Lima.zip"
EXTRACT_ROOT="Lima"   # top-level dir inside Lima.zip

# band|param-encoding
VARIANTS=(
  "easy|n262"
  "medium|n382"
  "hard|n502"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$SCRIPT_DIR/variant_patches/patch_lima.py" "$TMP/$EXTRACT_ROOT" "$BAND"

  # Repack into the same archive name with the same internal layout.
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Strip patch artifacts from the shipped task (keep them out of Docker ctx).
  rm -rf "$VARIANT_DIR/variant_patches"
done
