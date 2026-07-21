#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="Edon-RUpdate.zip"
EXTRACT_ROOT="Edon-R"   # top-level dir inside the archive
TARGET_REL="Reference_Implementation/Edon-R_ref.c"  # relative to EXTRACT_ROOT

# Approach A per algorithm_scaling_down/nist_sha3/round_1/EDON-R.txt and
# variant_workfolder/final_fixes_recommendation.md (Section 2, "EDON-R"):
#
#   Hard   (2^60–2^80): ROUNDS = 8  — UNMODIFIED upstream (4 rows × 2 Q*).
#   Medium (2^40–2^60): ROUNDS = 6  — Drop row 3 of the unrolled
#                                     compression (keep rows 1, 2, 4).
#   Easy   (2^30–2^40): ROUNDS = 4  — Drop rows 2 and 3 (keep rows 1, 4).
#
# Row 4 always writes `p256[0..15]` / `p512[0..15]` — the slots that
# `Final()` reads to produce the digest — so keeping it preserves the
# pipe-slot wiring contract of the recipe (the last surviving row's
# outputs always become the pipe slots).
#
# The weakening is applied at GENERATION time: each variant's copy of the
# upstream archive is unzipped, patched in place by the committed Python
# helper in ./variant_patches/, and repacked into the SAME archive name.
# build_cli.sh therefore stays byte-identical to base and nothing
# weakening-related ships inside environment/ (the Docker build context).
#
# band|ROUNDS|comma-separated rows to drop ("" = no patch, hard band)
A_VARIANTS=(
    "easy|4|2,3"
    "medium|6|3"
    "hard|8|"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R DROPS <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    if [ -n "$DROPS" ]; then
        # Unzip the variant's own archive copy, apply the row-drop patch
        # to the extracted source, then repack into the same archive name.
        ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
        TMP="$(mktemp -d)"
        unzip -q -o "$ARCH" -d "$TMP"
        python3 "$SCRIPT_DIR/variant_patches/patch_edon_r.py" \
            "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$DROPS"
        rm -f "$ARCH"
        ( cd "$TMP" && zip -q -r -X "$ARCH" . )
        rm -rf "$TMP"
    fi

    # Drop the patch artifacts from the generated variant — they live at
    # the algorithm root and must never enter the build context.
    rm -rf "$VARIANT_DIR/variant_patches"
done
