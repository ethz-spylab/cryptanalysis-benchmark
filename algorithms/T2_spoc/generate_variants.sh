#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

# Approach A (reduce NUMSTEPS). Per algorithm_scaling_down/nist_lwc/round_2/
# spoc.txt + MEDIUM_VARIANTS_ADDENDUM.md:
#   - Hard   (2^60–2^80): NUMSTEPS = 7
#   - Medium (2^40–2^60): NUMSTEPS = 6 (from addendum)
#   - Easy   (2^30–2^40): NUMSTEPS = 5
#
# Upstream sliscp_light256.h declares NUMSTEPSFULL = 18 — that's the AEAD's
# outer sliscp-light permutation step count. Round-constant tables are sized
# for 18 entries, so reductions are safe.
#
# Approach B and C are intentionally not implemented (policy: A only).

A_VARIANTS=(
    "easy|5"
    "medium|6"
    "hard|7"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NUMSTEPS <<< "$entry"
    SUFFIX="${BAND}_numsteps${NUMSTEPS}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    BUILD_SH="$VARIANT_DIR/environment/algorithm_src/build_cli.sh"
    PATCH_BLOCK="\\
# Variant patch: NUMSTEPSFULL = ${NUMSTEPS} (A-band ${BAND}).\\
sed -i -E 's/^#define NUMSTEPSFULL[[:space:]]+18$/#define NUMSTEPSFULL ${NUMSTEPS}/' spoc/Implementations/crypto_aead/spoc128sliscplight256v1/ref/sliscp_light256.h\\
"
    sed -i "/^unzip -q spoc.zip$/a ${PATCH_BLOCK}" "$BUILD_SH"
done
