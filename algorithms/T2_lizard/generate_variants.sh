#!/bin/bash
# Approach A (reduce LWE_N) per algorithm_scaling_down/nist_pqc/lizard.txt
#   Hard LWE_N=288  Medium LWE_N=200  Easy LWE_N=144   (real shipped value = 536)
# Only the LWE secret dimension n is reduced; q (LOG_Q=11), p (LOG_P=9),
# NOISE_D1, LWE_M=1024, LWE_L=256 and HR=140 are held fixed, so the rounding
# arithmetic, the Gaussian sampler and all M/L-derived serialized sizes stay
# correct and decryption stays per-coordinate correct.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same Lizard.zip name so build_cli.sh
# stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Lizard.zip"
EXTRACT_ROOT="NISTLizardFinal"   # top-level dir inside Lizard.zip; patch -d resolves against it

# band|param-encoding|patch-file
VARIANTS=(
  "easy|n144|variant_easy.patch"
  "medium|n200|variant_medium.patch"
  "hard|n288|variant_hard.patch"
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
  # Patch paths are prefixed with the archive's top dir ($EXTRACT_ROOT), so -p1
  # against $TMP resolves to $TMP/$EXTRACT_ROOT/Reference_Implementation/...
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  chmod -R u+w "$TMP"
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
