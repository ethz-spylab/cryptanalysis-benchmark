#!/bin/bash
# Approach A (reduce module rank d, vary log2N -> DIGITS) per
# algorithm_scaling_down/nist_pqc/round_2/ThreeBears-Round2.txt +
# MEDIUM_VARIANTS_ADDENDUM.md. All three bands set DIM=1 and vary DIGITS as
# 312 / 420 / 624 (easy / medium / hard). The reference impl parameterises the
# modulus as 2^(LGX*DIGITS) - 2^(LGX*DIGITS/2) - 1 with LGX=10, so the spec's
# "log2N" maps to DIGITS (baseline 312).
#
# Patch sites (all in BabyBear, upstream baselines DIM=2 DIGITS=312 PK=804 CT=917):
#   params.h: DIM, DIGITS ; api.h: CRYPTO_PUBLICKEYBYTES, CRYPTO_CIPHERTEXTBYTES
#   (GF_BYTES = (LGX*DIGITS+7)/8 ; PK = MATRIX_SEED_BYTES + DIM*GF_BYTES ;
#    CT = DIM*GF_BYTES + 137.)  Bands whose PK/CT/DIGITS already equal the
#   upstream baseline carry no edit for that field (hard keeps PK/CT; easy keeps
#   DIGITS) -- this matches the original build-time injection exactly.
#
# Mechanism: generation-time patch + repack. The per-band weakening lives in
# committed unified-diff patches under ./variant_patches/ (algorithm ROOT,
# OUTSIDE environment/ => never in the Docker build context => invisible to the
# agent). For each band we cp the algorithm, unzip the variant's archive, apply
# the band patch, repack into the SAME archive name, then drop variant_patches/.
# build_cli.sh is left byte-identical to base -- no injection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="ThreeBears-Round2.zip"
EXTRACT_ROOT="ThreeBears"   # top-level dir inside the archive; patch -p1 -d resolves here

# band|D|DIGITS|patch-file  (folder suffix encodes the real param values)
A_VARIANTS=(
    "easy|1|312|variant_easy.patch"
    "medium|1|420|variant_medium.patch"
    "hard|1|624|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND D DGT PATCH <<< "$entry"
    SUFFIX="${BAND}_d${D}_digits${DGT}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    chmod -R u+w "$TMP" 2>/dev/null || true
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
