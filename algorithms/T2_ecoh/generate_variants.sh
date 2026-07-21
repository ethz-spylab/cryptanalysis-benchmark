#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

# Approach A per algorithm_scaling_down/nist_sha3/round_1/ECOH.txt:
#   Hard   (2^60–2^80): curve B-163  — NOT IMPLEMENTED, see IMPLEMENTATION_NOTES.md
#   Medium (2^40–2^60): curve B-131  — NOT IMPLEMENTED, see IMPLEMENTATION_NOTES.md
#   Easy   (2^30–2^40): curve B-89   — NOT IMPLEMENTED, see IMPLEMENTATION_NOTES.md
#
# The shipped reference (`ecoh.h` + `ecoh.param.c`) implements only NIST
# binary curves B-283, B-409, B-571. Switching to B-163 / B-131 / B-89
# requires brand-new curve constants (irreducible polynomial, base point,
# group order, reduction routines) that aren't present in any form in
# the upstream — well beyond a sed patch.
#
# We ship the unmodified upstream as the only variant ("baseline"). It
# is *not* in any of the three target bands (B-283 ECDLP ≈ 2^140), so
# the security claim should be read as "above hard band". This is the
# best we can do without a curve-arithmetic rewrite. See
# `algorithm_scaling_down/IMPLEMENTATION_NOTES.md`.

A_VARIANTS=(
    "hard|283"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND CURVE <<< "$entry"
    SUFFIX="${BAND}_b${CURVE}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # No code patch: hard variant = unmodified upstream (B-283 curve).
done
