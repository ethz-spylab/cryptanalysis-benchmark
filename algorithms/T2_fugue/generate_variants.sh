#!/bin/bash
# Approach A: reduce final-SMIX (G2) round count for Fugue-256.
# Spec (algorithm_scaling_down/nist_sha3/round_2/Fugue_Round2.txt) + addendum:
#   - Hard   (2^60-2^80): final SMIX (t) = 6
#   - Medium (2^40-2^60): final SMIX (t) = 5
#   - Easy   (2^30-2^40): final SMIX (t) = 4
# Upstream: the per-hashbitlen config table in fugue.c declares the 256-bit
# row as `{256,{8 ,30,2,5,13},{0}}` — fields are {n, s, k, r, t}; `t` is the
# number of G2 (final) SMIX iterations (default 13). The default cli
# hashbitlen = 256, so only this row matters.
#
# Concealment design: the weakening is applied at GENERATION time. The patch
# helper lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so it never enters the Docker build context and is invisible
# to the agent. We unzip the variant's archive, patch the extracted source,
# repack it under the SAME archive name, and drop the patch helper — so
# build_cli.sh stays byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Fugue_Round2_Update.zip"
EXTRACT_ROOT="FugueTweak"
TARGET_REL="Reference_Implementation/fugue.c"

# band|t-value
A_VARIANTS=(
    "easy|4"
    "medium|5"
    "hard|6"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND T <<< "$entry"
    SUFFIX="${BAND}_t${T}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    python3 "$SCRIPT_DIR/variant_patches/patch_fugue.py" \
        "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$T"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
