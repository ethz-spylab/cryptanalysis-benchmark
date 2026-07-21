#!/bin/bash
# Approach A (reduce per-byte step count) per
#   algorithm_scaling_down/nist_sha3/round_1/MCSSHA3.txt
#   algorithm_scaling_down/MEDIUM_VARIANTS_ADDENDUM.md
# and the structural recipe in
#   variant_workfolder/final_fixes_recommendation.md (Section 2, MCSSHA-3).
#
# The reference (`mcssha3.c`) implements the per-byte work as
# 1 main register update + a delay loop `for(k=0;k<3;k++)` in Update().
# The spec's STEPS macro doesn't exist as a literal, but the delay loop
# count is the per-byte cryptographic-cost knob: shrinking it linearly
# reduces an attacker's per-byte work. We expose the loop bound as the
# variant parameter MCSSHA3_DELAY:
#   Hard:   3 (1 main + 3 delay; unmodified upstream).
#   Medium: 2 (1 main + 2 delay; ~25% less per-byte work).
#   Easy:   1 (1 main + 1 delay; ~50% less per-byte work).
# The Final() loop is left alone — it is driven by databitlen and is the
# buffer-alignment driver, not the per-byte cryptographic cost.
#
# Concealment: the weakening is applied at GENERATION time by patching the
# extracted upstream source and repacking it into the SAME archive name, so
# the shipped build_cli.sh stays byte-identical to the base and no patch
# artifact enters the Docker build context. The patch helper lives at the
# algorithm ROOT (./variant_patches/, a sibling of environment/) and is
# removed from each variant after use.
#
# Format: <band>|<delay>
A_VARIANTS=(
    "hard|3"
    "medium|2"
    "easy|1"
)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="MCSSHA3.zip"
EXTRACT_ROOT="MCSSHA3"                       # top-level dir inside the archive
TARGET_REL="Reference Implementation/mcssha3.c"

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND DELAY <<< "$entry"
    SUFFIX="${BAND}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    if [ "$DELAY" != "3" ]; then
        # Patch the extracted upstream source to the band's delay value and
        # repack into the SAME archive name so build_cli.sh stays pristine.
        ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
        TMP="$(mktemp -d)"
        unzip -q -o "$ARCH" -d "$TMP"
        python3 "$SCRIPT_DIR/variant_patches/patch_mcssha3.py" \
            "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$DELAY"
        ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
        rm -rf "$TMP"
    fi

    rm -rf "$VARIANT_DIR/variant_patches"
done
