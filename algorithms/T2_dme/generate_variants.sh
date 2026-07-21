#!/bin/bash
# Approach A (reduce field extension degree e) per algorithm_scaling_down/nist_pqc/dme.txt
#   Hard   e=42 (q=2^42, ~2^60-2^80)
#   Medium e=30 (q=2^30, ~2^40-2^60)
#   Easy   e=21 (q=2^21, ~2^30-2^40)
#
# DME-KEM hard-wires e=48 across the reference tree (Fq loop bound / 1<<48 mask /
# % 48 Frobenius, 96=2e for Fq2, 144=3e for Fq3, and the field modulus min_poly).
# variant_patches/patch_dme.py rewrites every site for a new degree and supplies
# a degree-e irreducible binary polynomial as the new min_poly; the build's
# setup/ helpers then regenerate all derived constants (exponents, extension
# moduli, M1/M2, pt_sec2pub) for the smaller field.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same DME.zip name so build_cli.sh
# stays pristine. The committed original archive is never modified.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="DME.zip"
EXTRACT_ROOT="DME"   # top-level dir inside DME.zip
REF_REL="DME/Reference_Implementation"

# band|param-encoding|e|min_poly (degree-e irreducible binary polynomial)
#   e=21: x^21+x^2+1   e=30: x^30+x+1   e=42: x^42+x^7+1
VARIANTS=(
  "easy|e21|21|0x200005"
  "medium|e30|30|0x40000003"
  "hard|e42|42|0x40000000081"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC E MINPOLY <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"
  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_dme.py" "$TMP/$REF_REL" "$E" "$MINPOLY"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"
  rm -rf "$VARIANT_DIR/variant_patches"
done
