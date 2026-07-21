#!/bin/bash
# Approach A (reduce Vortex AES_ROUNDS) per
# algorithm_scaling_down/nist_sha3/round_1/Vortex.txt and
# MEDIUM_VARIANTS_ADDENDUM.md (Vortex (R1) row).
# Spec values (per the spec convention "AES_ROUNDS"):
#   Hard   (2^60-2^80): AES_ROUNDS = 4
#   Medium (2^40-2^60): AES_ROUNDS = 3
#   Easy   (2^30-2^40): AES_ROUNDS = 2
#
# The reference impl exposes the round count as a *runtime* tunable
# (`number_of_rounds_g`) initialized in `set_default_parameters()` (vortex_core.c)
# to the literal `10`. The Hash() entry point calls `set_default_parameters()`
# before each compression, so patching the literal is sufficient.
#
# Note: upstream's default of 10 is higher than the spec's "full = 4" baseline;
# all three bands are reduced from 10. MAX_NUMBER_OF_ROUNDS = 15 so reductions
# are safe with respect to the rcon table sizing.
#
# The weakening is applied at GENERATION time: each variant's copy of the
# upstream archive is unzipped, patched in place by the committed Python helper
# in ./variant_patches/ (which lives at the algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent),
# and repacked into the SAME archive name. build_cli.sh therefore stays
# byte-identical to base and nothing weakening-related ships inside environment/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="VortexUpdate.zip"
EXTRACT_ROOT="VortexUpdate"   # top-level dir inside the archive
TARGET_REL="Reference_Implementation/SHA3_vortex/vortex_core.c"  # relative to EXTRACT_ROOT

# band|AES_ROUNDS
VARIANTS=(
    "easy|2"
    "medium|3"
    "hard|4"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND R <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Unzip the variant's own archive copy, apply the AES_ROUNDS reduction to
    # the extracted source, then repack into the same archive name.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    python3 "$SCRIPT_DIR/variant_patches/patch_vortex.py" \
        "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$R"
    rm -f "$ARCH"
    ( cd "$TMP" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Drop the patch artifacts from the generated variant — they live at the
    # algorithm root and must never enter the build context.
    rm -rf "$VARIANT_DIR/variant_patches"
done
