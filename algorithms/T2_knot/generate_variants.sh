#!/bin/bash
# Approach A (reduce KNOT nr0 -- initialisation rounds) per
# algorithm_scaling_down/nist_lwc/round_2/knot.txt and
# MEDIUM_VARIANTS_ADDENDUM.md (knot row).
#
# Note on upstream parameter mismatch: the spec text targets KNOT-AEAD-128
# with b=256 and nr0=52 ("(52 full)" in the addendum). Our build_cli.sh
# uses the upstream `knot128v2/ref` (b=384, nr0=76). We follow the spec's
# explicit hard/medium/easy targets (14/12/9) regardless of the upstream
# baseline -- the variant values are large reductions in either parameter
# regime.
#   Hard   (2^60-2^80): nr0 = 14
#   Medium (2^40-2^60): nr0 = 12
#   Easy   (2^30-2^40): nr0 =  9
# `nr` and `nrf` are left at their upstream values (28 and 32). The
# `int nr0 = 76;` literal occurs twice in encrypt.c (encrypt + decrypt
# functions); both must match, and each band patch rewrites both.
#
# Concealment design: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in
# the Docker build context => invisible to the agent). encrypt.c ships in the
# upstream zip, so at generation time we unzip the variant's archive, apply
# the band patch, and repack into the SAME archive name. build_cli.sh is left
# byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="knot.zip"
EXTRACT_ROOT="knot"   # top-level dir inside knot.zip; patch -d resolves against it

# band|nr0-value|patch-file
VARIANTS=(
    "easy|9|variant_easy.patch"
    "medium|12|variant_medium.patch"
    "hard|14|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND NR0 PATCH <<< "$entry"
    SUFFIX="${BAND}_nr0_${NR0}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
