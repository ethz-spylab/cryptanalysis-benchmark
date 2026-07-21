#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="subterranean.zip"
# Target source file inside the extracted archive (top dir is "subterranean").
TARGET_REL="subterranean/Implementations/crypto_aead/subterraneanv1/ref/subterranean_ref.c"

# Approach A (reduce permutation rounds). Per algorithm_scaling_down/
# nist_lwc/round_2/subterranean.txt + MEDIUM_VARIANTS_ADDENDUM.md, the
# spec lists rounds = 4 / "4 + last χ-stripped" / 3 for hard / medium /
# easy.
#
# Upstream subterranean_ref.c performs the 8 blank rounds between blocks
# via 11 calls of the form `subterranean_blank(state, 8)` (one per
# init/finalisation phase). Reducing the literal `8` to R changes the
# blank-round count uniformly across all phases, which is the spec's
# Approach A.
#
# Mapping spec → patch:
#   - Hard   rounds = 4 ✓
#   - Medium "4 rounds + last χ-stripped" — recovered per
#     variant_workfolder/final_fixes_recommendation.md (Section 1,
#     "Subterranean"). Implemented via patch_subterranean_medium.py:
#     introduce subterranean_round_no_chi (iota + theta + pi only) and
#     replace the finalisation blank inside
#     subterranean_SAE_direct_encrypt / _decrypt with (rounds-1) normal
#     duplex calls followed by 1 no-χ round.
#   - Easy   rounds = 3 ✓
#
# Weakening is applied at generation time by patching the extracted source
# and repacking the SAME archive name, so build_cli.sh stays byte-identical
# to the shipped full-strength original and no weakening artifact ever
# enters the Docker build context (the patch helper lives at the algorithm
# root in ./variant_patches/, outside environment/, and is removed from
# every generated variant).
#
# Approach B (weaken χ) and C (shrink key entropy) are intentionally
# not implemented (policy: A only).

# band|rounds|nochi
A_VARIANTS=(
    "easy|3|0"
    "medium|4|1"
    "hard|4|0"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ROUNDS NOCHI <<< "$entry"
    SUFFIX="${BAND}_rounds${ROUNDS}"
    if [ "$NOCHI" = "1" ]; then
        SUFFIX="${BAND}_rounds${ROUNDS}_lastnochi"
    fi
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    # Approach-A blank-round reduction (8 -> ROUNDS) across all phases.
    sed -i "s/subterranean_blank(state, 8)/subterranean_blank(state, ${ROUNDS})/g" "$TMP/$TARGET_REL"

    # Medium band only: strip χ from the very last finalisation round.
    if [ "$NOCHI" = "1" ]; then
        python3 "$SCRIPT_DIR/variant_patches/patch_subterranean_medium.py" "$TMP/$TARGET_REL"
    fi

    # Repack into the SAME archive name, reproducing the original layout.
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
