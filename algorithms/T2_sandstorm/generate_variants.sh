#!/bin/bash
# SANDstorm scaling-down variants (Approach A: structural round reduction).
#
# Per `variant_workfolder/final_fixes_recommendation.md` § SANDstorm we delete
# trailing unrolled `do_round` calls inside `Do_Block_ModMix_Ref`. The TSP
# extension loop and `round4_out` are preserved (a feedforward-style finaliser
# that remains correct regardless of the inner round count).
#
#   Hard   (2^60-2^80): keep rounds 0..3 (4 unrolled rounds; one fewer than
#                       upstream's 5).
#   Medium (2^40-2^60): keep rounds 0..2 (3 unrolled rounds).
#   Easy   (2^30-2^40): keep rounds 0..1 (2 unrolled rounds).
#
# The weakening is applied at GENERATION time: the patch helper in
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent) edits the SHA3api_ref.c
# inside a temp extraction of the variant's SANDstorm.zip, then the source is
# repacked into the SAME archive name. build_cli.sh stays byte-identical to
# base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="SANDstorm.zip"
# Path of the patched file inside the archive's extracted tree.
TARGET_REL="SANDstorm/SANDstorm/Reference_Implementation/SHA3api_ref.c"

# <band>|<R>
A_VARIANTS=(
    "easy|2"
    "medium|3"
    "hard|4"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    chmod -R u+w "$TMP"
    python3 "$SCRIPT_DIR/variant_patches/patch_sandstorm.py" "$R" "$TMP/$TARGET_REL"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
