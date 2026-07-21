#!/bin/bash
# Approach A (reduce ROUNDS) per
#   algorithm_scaling_down/nist_sha3/round_2/Shabal_Round2.txt
# and MEDIUM_VARIANTS_ADDENDUM.md.
#
# Per algorithm_scaling_down/IMPLEMENTATION_NOTES.md, the upstream
# `shabal.c` exposes only SHABAL_PARAM_P and `sM` (which doubles as the
# message-block width). Macro-only flips reach {16, 32, 48} total inner
# operations -- none of which match the spec's hard / medium / easy
# round counts.
#
# Per variant_workfolder/final_fixes_recommendation.md (Section 2,
# "Shabal"), the structural fix introduces a separate compile-time
# constant SHABAL_ROUNDS_PER_BLOCK that controls the inner-permutation
# loop bound, leaving `sM` untouched (so the message-block layout is
# preserved). The two textually-identical loops in apply_perm() are
# disambiguated by their unique `u32 tB;` body declaration; the
# rewrite is delivered by patch_shabal.py.
#
# Variant tuples (band | P | ROUNDS_PER_BLOCK | total inner ops):
#   Hard   P=3, RPB=6 -> 18 total (matches addendum hard 18)
#   Medium P=3, RPB=5 -> 15 total (between addendum medium 14 and easy 10)
#   Easy   P=2, RPB=5 -> 10 total (matches addendum easy 10)
#
# Concealment: the weakening patch lives in ./variant_patches/ (algorithm
# ROOT, outside environment/ => never in the Docker build context =>
# invisible to the agent). The patch bakes the band's P / RPB directly
# into the extracted shabal.c and the source is repacked into the same
# archive name, so build_cli.sh stays byte-identical to the base task
# (no `-D` flags are injected).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Shabal_Round2.zip"
EXTRACT_ROOT="Shabal"                       # top-level dir inside the archive
TARGET_REL="Shabal/Reference_Implementation/shabal.c"

A_VARIANTS=(
    "easy|2|5"
    "medium|3|5"
    "hard|3|6"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND P RPB <<< "$entry"
    SUFFIX="${BAND}_p${P}_rpb${RPB}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    # Bake the band's P / RPB into the extracted source.
    python3 "$SCRIPT_DIR/variant_patches/patch_shabal.py" \
        "$TMP/$TARGET_REL" "$P" "$RPB"

    # Repack into the SAME archive name with the SAME internal layout
    # (top-level dir preserved) so build_cli.sh stays pristine.
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" "$EXTRACT_ROOT" )
    rm -rf "$TMP"

    # Drop the patch artifacts so they never ship in the variant.
    rm -rf "$VARIANT_DIR/variant_patches"
done
