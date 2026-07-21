#!/bin/bash
# Approach A — secondary-parameter weakening per
# variant_workfolder/final_fixes_recommendation.md ("LAC"). LAC's reference
# pre-computes PK_LEN, CIPHER_LEN, C2_VEC_NUM, SAMPLE_LEN from DIM_N + a BCH
# layer keyed on DATA_LEN/ECC_LEN, so reducing DIM_N requires a BCH-aware
# rewrite. Instead we hold DIM_N (= 512 for LAC128) fixed and reduce the
# Hamming weight NUM_ONE of the signed-binary LWE noise vector. Q is held at
# the upstream value (251) across all bands (smaller moduli make the BCH layer
# fail to correct the d2-decoder's residual signal-to-noise loss); LWE security
# scales ~exponentially in NUM_ONE for fixed Q, so the bands stay spaced.
#
# Bands:
#   Hard   (~2^70): NUM_ONE=96
#   Medium (~2^50): NUM_ONE=64
#   Easy   (~2^32): NUM_ONE=32
#
# Concealment design (generation-time repack): the weakening patcher lives in
# ./variant_patches/ at the algorithm ROOT (a sibling of environment/, so it is
# never part of the Docker build context and never ships in the image). For
# each band we unzip the variant's vendored archive, apply the patcher to the
# extracted lac_param.h, and repack into the SAME archive name. build_cli.sh is
# left byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="vendored-LAC.tar.gz"
# tar extracts to LAC/ ; lac_param.h lives at LAC/LAC-v3a/ref/lac_param.h
PARAM_REL="LAC/LAC-v3a/ref/lac_param.h"

# Format: <band>|<NUM_ONE>|<Q>
A_VARIANTS=(
    "easy|32|251"
    "medium|64|251"
    "hard|96|251"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NUM_ONE Q <<< "$entry"
    SUFFIX="${BAND}_n${NUM_ONE}_q${Q}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    tar xzf "$ARCH" -C "$TMP"
    python3 "$SCRIPT_DIR/variant_patches/patch_lac.py" "$TMP/$PARAM_REL" "$NUM_ONE"
    ( cd "$TMP" && rm -f "$ARCH" && tar czf "$ARCH" LAC )
    rm -rf "$TMP"

    # Drop the patch artifacts from the shipped variant (never enter the image).
    rm -rf "$VARIANT_DIR/variant_patches"
done
