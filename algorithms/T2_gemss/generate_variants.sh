#!/bin/bash
# Variant generator for T2_gemss (GeMSS128, HFEv- multivariate signature).
#
# Approach A (reduce HFEn = extension degree n = #variables/eqs base) per
# algorithm_scaling_down/nist_pqc/gemss.txt. Holding HFEDeg (D=513), HFEv (12)
# and HFEDELTA (12) fixed keeps the MinRank rank R and Groebner d_reg constant,
# so n is a clean monotone knob; the dominant support-minors MinRank cost
# ~ binom(n, R~22)^omega shrinks steeply as n drops.
#   Easy   HFEn=40U  -> ~2^34-2^38   (HFEm = 40-12 = 28 equations)
#   Medium HFEn=56U  -> ~2^46-2^52   (HFEm = 56-12 = 44 equations)
#   Hard   HFEn=78U  -> ~2^62-2^72   (HFEm = 78-12 = 66 equations)
# config_gf2n.h already defines the GF(2^n) irreducible-polynomial taps for all
# three n (supported contiguously for n in 2..103). Downstream byte-size macros
# in sizes_HFE.h / api.h are computed from HFEn/HFEv/HFEm and track on rebuild.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so they are outside the Docker build context => invisible to
# the agent. The weakened source is repacked into the SAME archive name so
# build_cli.sh stays byte-for-byte pristine. The committed original archive
# under $SCRIPT_DIR is never modified — only the per-variant copy is.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="GeMSS-Round3.zip"
EXTRACT_ROOT="GeMSS-Round3"   # top-level dir inside the archive; patch -d target

# band|param-encoding|patch-file
VARIANTS=(
  "easy|n40|variant_easy.patch"
  "medium|n56|variant_medium.patch"
  "hard|n78|variant_hard.patch"
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

  # Drop the patch artifacts from the variant so they never ship inside a task.
  rm -rf "$VARIANT_DIR/variant_patches"
done
