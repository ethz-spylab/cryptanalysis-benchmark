#!/bin/bash
# Approach A (reduce per-block / framing permutation step counts) per
# algorithm_scaling_down/nist_lwc/round_1/clx.txt and MEDIUM_VARIANTS_ADDENDUM.md:
#   Hard   (2^60–2^80): NROUND1 = 320, NROUND2 = 960
#   Medium (2^40–2^60): NROUND1 = 256, NROUND2 = 768
#   Easy   (2^30–2^40): NROUND1 = 192, NROUND2 = 576
# (upstream defaults: NROUND1 = 384, NROUND2 = 1152)
#
# These macros live in encrypt.c inside clx.zip, copied into algorithm_encrypt.c
# by build_cli.sh. The weakening is applied at GENERATION time: each variant's
# clx.zip is unzipped, the patcher in ./variant_patches/ rewrites the macros,
# and the tree is repacked into the SAME archive name — so build_cli.sh stays
# byte-identical to base. The patch artifacts live at the algorithm ROOT
# (outside environment/ => never in the Docker build context => invisible to
# the agent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="clx.zip"
EXTRACT_ROOT="clx"
TARGET_REL="Implementations/crypto_aead/clx128/ref/encrypt.c"

# band|NROUND1|NROUND2
A_VARIANTS=(
    "easy|192|576"
    "medium|256|768"
    "hard|320|960"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND N1 N2 <<< "$entry"
    SUFFIX="${BAND}_n1_${N1}_n2_${N2}"
    if [[ "$BAND" == "medium" ]]; then
        # Drop n1_/n2_ letter prefixes for the medium variant only:
        # with them, the directory name ends in "..._n2_768" and char 32
        # lands on "_". Harbor truncates trial names to 32 and joins with
        # "__", producing "___" in the docker compose project name —
        # invalid per https://github.com/distribution/reference image-ref
        # grammar (separators may not be adjacent).
        SUFFIX="${BAND}_${N1}_${N2}"
    fi
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Generation-time repack: weaken the variant's own archive copy in place.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    python3 "$SCRIPT_DIR/variant_patches/patch_clx.py" \
        "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$N1" "$N2"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
