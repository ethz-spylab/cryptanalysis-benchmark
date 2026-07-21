#!/bin/bash
# Approach A (reduce the OUTER round count of the compression function) for
# Dynamic SHA2 (NIST SHA-3 Round 1).
#
# Upstream: DynamicSHA_2.zip :: "DynamicSHA_2/Reference Implementation/dsha2_Ref.h".
# The security knob is the outer loop `for ( i=0; i<8; i++ )` present in BOTH
# compression functions (sha32_compile -> 256-bit default digest, sha64_compile
# -> 512-bit digest). FULL strength = 8. We reduce both (kept equal) per band:
#   Hard   : 6
#   Medium : 4
#   Easy   : 2
#
# CAVEAT (recorded honestly): in Dynamic SHA2 the outer round count also gates
# which 512-bit-block message words get absorbed (w[i+i1]); reducing it below 8
# means some message words are never mixed in, so ALL reduced bands admit fast
# collisions. That is acceptable and intended for these deliberately-weakened
# "easier" variants (the full-strength T2_dynamicsha2 task remains the hard one).
# The bands differ in degree of weakness, not in a cleanly-quantified security
# level.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enters the Docker build context => invisible to the
# agent). The weakened source is repacked into the SAME vendored archive name so
# build_cli.sh stays byte-identical (pristine).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"        # algorithm root
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="DynamicSHA_2.zip"
EXTRACT_ROOT="DynamicSHA_2"                         # top-level dir inside the archive
HEADER_REL="Reference Implementation/dsha2_Ref.h"  # note: contains a space
PATCHER="$SCRIPT_DIR/variant_patches/patch_dynamicsha2.py"

# band|param-encoding|rounds
VARIANTS=(
    "easy|r2|2"
    "medium|r4|4"
    "hard|r6|6"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC ROUNDS <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f  "$VARIANT_DIR/generate_variants.sh"      # stripped anyway; keep copy clean

    # Apply the weakening to the extracted source, then repack into the SAME
    # archive name so build_cli.sh's unzip step is unchanged. Repack target is
    # the VARIANT copy's archive, NEVER $SCRIPT_DIR's committed original.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$HEADER_REL" "$ROUNDS"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Do NOT ship variant_patches/ into the generated task. It sits at the
    # variant root (outside environment/) so it never enters the image, but
    # remove it to keep the generated task folder clean.
    rm -rf "$VARIANT_DIR/variant_patches"
done
