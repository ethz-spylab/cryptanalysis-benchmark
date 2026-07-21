#!/bin/bash
# Approach A (reduce BIG_ROUNDS) per
#   algorithm_scaling_down/nist_sha3/round_2/ECHO_Round2.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (hard=4, medium=3*, easy=3).
#
# Generation-time patch + repack. The ECHO reference has no BIG_ROUNDS
# macro in echo.h; the round count is set in echo_ref.c via
# `state->rounds = 8;` for hashbitlen <= 256 (the default the cli uses).
# Each band's edit is delivered as a committed patch artifact under
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent). We unzip the variant's
# own copy of ECHO_Round2.zip, apply the patch, repack into the SAME
# archive name, and drop variant_patches/ from the variant. build_cli.sh
# is therefore byte-identical to base and the committed original archive is
# never touched.
#
# Medium recovery per variant_workfolder/final_fixes_recommendation.md
# (Section 2, "ECHO"). The addendum's medium = R=3* collapses with easy
# at the macro level. To produce a genuine medium between hard R=4 and
# easy R=3, we ship R=3 *plus* an extra partial round (SubByte step only,
# no BigShiftRows / BigMixColumns / AddRoundKey) appended after the
# round loop. The S-box alone contributes the AES non-linearity layer
# (~2^8 differential cost), placing the medium variant between the two
# bracketing R values. The partial-round insertion is delivered by
# patch_echo_medium.py (multi-line edit, beyond a clean unified diff).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="ECHO_Round2.zip"
EXTRACT_ROOT="ECHO"   # the dir the patch -p1 -d resolves against
TARGET="Reference_Implementation/echo_ref.c"

# entry := band|suffix|round-patch|partial-round (1 = append SubByte-only, 0 = don't)
A_VARIANTS=(
    "easy|easy_r3|variant_easy.patch|0"
    "medium|medium_r3_plus_subbytes|variant_medium.patch|1"
    "hard|hard_r4|variant_hard.patch|0"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND SUFFIX PATCH PARTIAL <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    # Apply the round-count reduction (committed unified diff).
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"

    # Medium band: append the SubByte-only partial round.
    if [ "$PARTIAL" = "1" ]; then
        python3 "$SCRIPT_DIR/variant_patches/patch_echo_medium.py" \
            "$TMP/$EXTRACT_ROOT/$TARGET"
    fi

    # Repack into the SAME archive name with the SAME internal layout.
    rm -f "$ARCH"
    ( cd "$TMP" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Drop the patch artifacts from the variant (they never ship in the image).
    rm -rf "$VARIANT_DIR/variant_patches"
done
