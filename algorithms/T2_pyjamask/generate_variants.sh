#!/bin/bash
# Approach A: reduce NB_ROUNDS_128 in pyjamask.c.
# Bands per algorithm_scaling_down/nist_lwc/round_2/pyjamask.txt + addendum:
#   Hard (2^60-2^80): NB_ROUNDS_128 = 9
#   Medium (2^40-2^60): NB_ROUNDS_128 = 8
#   Easy (2^30-2^40): NB_ROUNDS_128 = 7
# Upstream baseline: NB_ROUNDS_128 = 14.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent. The weakened source is repacked into the same pyjamask.zip name so
# build_cli.sh stays byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="pyjamask.zip"

# band|round-count|patch-file
A_VARIANTS=(
    "easy|7|variant_easy.patch"
    "medium|8|variant_medium.patch"
    "hard|9|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    chmod -R u+w "$TMP"
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
