#!/bin/bash
# Approach A (reduce the number of FINALIZATION rounds) for SHAMATA
# (SHAMATA-256, NIST SHA-3 Round 1). T1->T2 reclassified: no proposal file, the
# knob + bands are DERIVED from source (see algorithm_scaling_down/
# IMPLEMENTATION_NOTES.md, Part 3).
#
# Upstream: SHAMATA.zip ::
#   "SHAMATA Tubitak UEKAE/Reference Implementation/ShamataReference.c".
# The security knob is the finalization loop in Final():
#   for(i=0;i<32;i++) UpdateRegister(state,RData,state->r,i+1);
# This 32-iteration loop performs the bulk of the state diffusion / output
# whitening. FULL strength = 32. We reduce it per band:
#   Hard   : 16
#   Medium : 8
#   Easy   : 4
# Fewer finalization rounds -> weaker avalanche -> reduced-round differential /
# birthday collisions become findable (the intended weakening; the
# full-strength T2_shamata task remains the hard one). The 2^60-80 / 2^40-60 /
# 2^30-40 collision-work targets are BEST-EFFORT: the mapping to a bit level is
# not anchored to a published cryptanalysis, so we ship monotone reduced round
# counts (hard>medium>easy, all strictly < 32) and say so honestly.
#
# The r=1 ARF-count knob was NOT used: at the CLI default hashbitlen=256 the
# reference sets state->r=1 (Init), so it admits no reduced value >0 and cannot
# yield three monotone bands.
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
ARCHIVE="SHAMATA.zip"
EXTRACT_ROOT="SHAMATA Tubitak UEKAE"               # top-level dir inside the archive (has a space)
SRC_REL_IN_ARCHIVE="Reference Implementation/ShamataReference.c"  # also has a space
PATCHER="$SCRIPT_DIR/variant_patches/patch_shamata.py"

# band|param-encoding|finalization-rounds
VARIANTS=(
    "easy|f4|4"
    "medium|f8|8"
    "hard|f16|16"
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
    python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$SRC_REL_IN_ARCHIVE" "$ROUNDS"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Do NOT ship variant_patches/ into the generated task (it sits at the
    # variant root, outside environment/, so it never enters the image, but
    # remove it to keep the generated task folder clean).
    rm -rf "$VARIANT_DIR/variant_patches"

    # Variants are challenge tasks: reset solution/ to only TODO.md.
    if [ -d "$VARIANT_DIR/solution" ]; then
        find "$VARIANT_DIR/solution" -type f ! -name 'TODO.md' -delete
    fi
done
