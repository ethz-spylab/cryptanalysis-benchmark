#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LANE.zip"
EXTRACT_ROOT="LANE"   # top-level dir inside LANE.zip; patch -p1 resolves against it

# Approach A (reduce per-lane AES-like round count of the P permutation) per
# algorithm_scaling_down/nist_sha3/round_1/LANE.txt + MEDIUM_VARIANTS_ADDENDUM.md.
#   Hard   (2^60-2^80): ROUNDS = 4
#   Medium (2^40-2^60): ROUNDS = 3 + partial (SubBytes + ShiftRows only)
#   Easy   (2^30-2^40): ROUNDS = 3
#
# The reference (laneref256.c) has no `#define ROUNDS` — the per-lane P
# permutation loops on `for(i=0; i!=5; i++)` (5 ordinary rounds + 1 final =
# 6 rounds). To get R rounds total we patch the loop bound to R-1. The Q
# permutation (`for(i=0; i!=2; i++)`, 3 rounds) is left untouched: the spec
# parameterises only the per-lane P round count. The cli's default
# hashbitlen is 256, so only laneref256.c is on the hot path.
#
# Medium recovery per variant_workfolder/final_fixes_recommendation.md
# (Section 2, "LANE"). The addendum's medium = R=3* collapses with easy.
# The fix runs R=3 plus an extra partial round (SubBytes + ShiftRows only,
# no MixColumns / SwapColumns) appended after the final special round in
# PermuteP256, delivered by patch_lane_medium.py.
#
# Concealment: the weakening patch artifacts live in ./variant_patches/ at the
# algorithm ROOT (a sibling of environment/), so they never enter the Docker
# build context and never ship in the image. The variant's source archive is
# patched + repacked at generation time into the SAME archive name, so
# build_cli.sh stays byte-identical to the base task.

# band | rounds | loop-bound patch | partial-round (1=yes)
A_VARIANTS=(
    "easy|3|variant_easy.patch|0"
    "medium|3|variant_medium.patch|1"
    "hard|4|variant_hard.patch|0"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ROUNDS PATCH PARTIAL <<< "$entry"
    SUFFIX="${BAND}_r${ROUNDS}"
    if [ "$PARTIAL" = "1" ]; then
        SUFFIX="${SUFFIX}_plus_subbytes_shiftrows"
    fi
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    # Apply the per-band loop-bound reduction to the extracted source.
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"

    # Medium band: append the partial round via the relocated helper.
    if [ "$PARTIAL" = "1" ]; then
        python3 "$SCRIPT_DIR/variant_patches/patch_lane_medium.py" \
            "$TMP/$EXTRACT_ROOT/Reference Implementation/laneref256.c"
    fi

    # Repack into the SAME archive name with the SAME internal layout.
    rm -f "$ARCH"
    ( cd "$TMP" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Drop the patch artifacts from the shipped variant (concealment).
    rm -rf "$VARIANT_DIR/variant_patches"
done
