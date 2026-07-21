#!/bin/bash
# Approach A (reduce step count) per
#   algorithm_scaling_down/nist_sha3/round_1/ARIRANG.txt
#   algorithm_scaling_down/MEDIUM_VARIANTS_ADDENDUM.md
# and the structural recipe in
#   variant_workfolder/final_fixes_recommendation.md (Section 2, ARIRANG).
#
# The reference unrolls 40 step256() calls in Arirang_Compression256 with
# Feedforward_1 after step 20 and Feedforward_2 after step 40. We ship a
# Python helper (patch_arirang.py) that rewrites the compression body
# parametrically: R step256 calls drawn from the upstream order, with
# Feedforward_1 inserted after step R/2. Feedforward_2 (the chaining-
# state update) is retained at the end so the hash composes across blocks.
#
#   Hard:   R=18 (steps 1..9, FF1, steps 10..18, FF2).
#   Medium: R=14 (steps 1..7, FF1, steps 8..14, FF2).
#   Easy:   R=12 (steps 1..6, FF1, steps 7..12, FF2).
#
# Note: spec says medium=15 but R must be even (FF1 at step R/2). We pick
# R=14 as the closest even value within the medium band.
#
# Concealment: the weakening helper (patch_arirang.py) lives in ./variant_patches/
# at the algorithm ROOT (a sibling of environment/), so it never enters the
# Docker build context and is invisible to the agent. Generation unzips the
# variant's vendored archive, applies the helper to the extracted source, and
# repacks into the SAME archive name, so build_cli.sh stays byte-identical to
# the base task and NOTHING weakening-related remains under environment/.
#
# Format: <band>|<R>
A_VARIANTS=(
    "hard|18"
    "medium|14"
    "easy|12"
)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="ARIRANGUpdate.zip"
# Directory inside the archive that holds the file patch_arirang.py rewrites
# (Arirang_Ref64.c). The helper hardcodes the relative filename, so we cd here
# before invoking it.
EXTRACT_SUBDIR="ARIRANG/Reference Implementation"

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R <<< "$entry"
    SUFFIX="${BAND}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Patch the variant's archive at generation time, then repack so the
    # pristine build_cli.sh transparently builds the weakened source.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    ( cd "$TMP/$EXTRACT_SUBDIR" && python3 "$SCRIPT_DIR/variant_patches/patch_arirang.py" "$R" )
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Strip the patch artifacts from the shipped variant so nothing weakening-
    # related remains anywhere in the build context.
    rm -rf "$VARIANT_DIR/variant_patches"
done
