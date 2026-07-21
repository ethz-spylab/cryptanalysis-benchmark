#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="spook-ref-implem-v2.0.zip"
# The archive has no wrapping top-level dir; crypto_aead/ is at the root, so the
# patch target resolves directly under the extraction dir.
TARGET_REL="crypto_aead/spook128su384v2/ref/primitives.c"

# Approach A (reduce Clyde-128 inner rounds). Per algorithm_scaling_down/
# nist_lwc/round_2/spook.txt + MEDIUM_VARIANTS_ADDENDUM.md, the spec lists
# rounds R = 4 / 3 / 2 for hard / medium / easy.
#
# Upstream Clyde-128 (primitives.c):
#   #define CLYDE_128_NS 6                // Number of steps
#   #define CLYDE_128_NR 2 * CLYDE_128_NS // Number of rounds (= 12)
# Each step performs 2 rounds (an inner `for (rho = 0; rho < 2; ...)`) plus
# a tweakey XOR. Round count is therefore always EVEN at the step
# granularity.
#
# We patch the two loop bounds in clyde128_encrypt / clyde128_decrypt to
# a smaller literal NS, leaving CLYDE_128_NS = 6 (and therefore the
# `clyde128_rc[CLYDE_128_NR][LS_ROWS]` table sizing) unchanged. The rc
# table just keeps unused trailing rows.
#
# Mapping spec rounds → NS:
#   - Hard   R = 4 → NS = 2 ✓
#   - Medium R = 3 → NS = 1.5 — recovered per
#     variant_workfolder/final_fixes_recommendation.md (Section 1, "Spook").
#     Implemented as NS = 1 plus one peeled inner-round iteration appended
#     to clyde128_encrypt and prepended (as inverse) to clyde128_decrypt
#     via variant_patches/patch_spook_medium.py.
#   - Easy   R = 2 → NS = 1 ✓
#
# Approach B and C are intentionally not implemented (policy: A only).
#
# Concealment design: the weakening is applied at GENERATION time by patching
# the extracted upstream source and repacking it into the SAME archive name,
# so each variant's build_cli.sh stays byte-identical to the base and no
# weakening artifact ever enters the Docker build context. Patch artifacts
# live in ./variant_patches/ (algorithm ROOT, a sibling of environment/), and
# the copy is stripped from each variant after repacking.

# band|NS|R|PEEL
A_VARIANTS=(
    "easy|1|2|0"
    "medium|1|3|1"
    "hard|2|4|0"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NS R PEEL <<< "$entry"
    SUFFIX="${BAND}_clyde_rounds${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    TARGET="$TMP/$TARGET_REL"
    # Reduce the Clyde-128 step-loop bound to NS (rounds = 2*NS).
    sed -i "s/s < CLYDE_128_NS;/s < ${NS};/" "$TARGET"
    sed -i "s/CLYDE_128_NS - 1/${NS} - 1/" "$TARGET"

    if [ "$PEEL" = "1" ]; then
        # Medium variant: peel one extra inner-round (encrypt append /
        # decrypt prepend-inverse) to realise R = 3 (NS = 1.5).
        python3 "$SCRIPT_DIR/variant_patches/patch_spook_medium.py" "$TARGET"
    fi

    # Repack the weakened source into the same archive name + internal layout.
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
