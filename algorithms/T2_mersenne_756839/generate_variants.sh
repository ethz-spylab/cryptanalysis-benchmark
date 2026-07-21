#!/bin/bash
# Variant generator for Mersenne-756839 (AJPS Mersenne-prime KEM).
#
# Approach: reduce the Mersenne exponent Psize (the prime 2^Psize - 1) and co-reduce
# the secret Hamming weight Hvalue, per algorithm_scaling_down/nist_pqc/mersenne_756839.txt.
# All chosen Psize values are genuine Mersenne-prime exponents (2^n - 1 is prime) and
# every pair respects the AJPS correctness constraint 4*h^2 < n.
#
#   Hard   Psize=23209 Hvalue=72   (4*72^2 = 20736 < 23209)
#   Medium Psize=9689  Hvalue=48   (4*48^2 =  9216 < 9689)
#   Easy   Psize=4423  Hvalue=32   (4*32^2 =  4096 < 4423)
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of environment/),
# so it is never part of the Docker build context and stays invisible to the agent.
# The weakened source is repacked into the SAME archive name so build_cli.sh stays pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Mersenne_756839.zip"
EXTRACT_ROOT="Mersenne_756839"                       # top-level dir inside the archive
KEMFILE="Reference_Implementation/Mersenne_kem.c"    # file holding Psize / Hvalue (compiled)

# band|folder-encoding|Psize|Hvalue
VARIANTS=(
  "easy|p4423h32|4423|32"
  "medium|p9689h48|9689|48"
  "hard|p23209h72|23209|72"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PSIZE HVALUE <<< "$entry"
  # Merge band+encoding (no separating underscore) so the 32-char trial-name
  # truncation never lands on a trailing '_'.
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$SCRIPT_DIR/variant_patches/patch_mersenne.py" \
          "$TMP/$EXTRACT_ROOT/$KEMFILE" "$PSIZE" "$HVALUE"

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Drop the patch artifacts from the shipped variant (concealment).
  rm -rf "$VARIANT_DIR/variant_patches"
done
