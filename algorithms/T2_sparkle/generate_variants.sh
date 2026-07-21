#!/bin/bash
set -euo pipefail

# Approach A (reduce SPARKLE_STEPS_SLIM). Per algorithm_scaling_down/nist_lwc/
# finalists/sparkle.txt + MEDIUM_VARIANTS_ADDENDUM.md, three A-band variants:
#   - Hard   (2^60-2^80): SPARKLE_STEPS_SLIM = 5
#   - Medium (2^40-2^60): SPARKLE_STEPS_SLIM = 4 (from addendum)
#   - Easy   (2^30-2^40): SPARKLE_STEPS_SLIM = 3
#
# Upstream Schwaemm256-128: STEPSSLIM = 7, STEPSBIG = 11. SCHWAEMM256_128
# is the only #if branch compiled in by schwaemm_cfg.h, but the literal
# `#define SPARKLE_STEPS_SLIM  7` appears in three #ifdef branches; replacing
# all is harmless because non-256_128 branches are not compiled.
#
# Mechanism: generation-time patch + repack. The weakening lives in the
# committed patch artifact ./variant_patches/patch_sparkle.py (algorithm ROOT,
# OUTSIDE environment/ => never in the Docker build context => invisible to the
# agent). We unzip the variant's archive, apply the patch, and repack into the
# SAME archive name so build_cli.sh stays byte-identical to base.
#
# Approach B and C are intentionally not implemented (policy: A only).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="sparkle.zip"
EXTRACT_ROOT="sparkle"
CFG_REL="Implementations/crypto_aead/schwaemm256128v2/ref/schwaemm_cfg.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_sparkle.py"

# band|steps_slim value
A_VARIANTS=(
    "easy|3"
    "medium|4"
    "hard|5"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND STEPS_SLIM <<< "$entry"
    SUFFIX="${BAND}_stepsslim${STEPS_SLIM}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$CFG_REL" "$STEPS_SLIM"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
