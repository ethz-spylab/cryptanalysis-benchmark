#!/bin/bash
# Approach A: reduce GIFT-128 ROUNDS per
# algorithm_scaling_down/nist_lwc/finalists/gift-cofb.txt + addendum.
#   Hard   ROUNDS=14   Medium ROUNDS=12   Easy ROUNDS=9
# Upstream baseline: 40 rounds, literal `for(round=0; round<40; round++)` in
# gift-cofb/Implementations/crypto_aead/giftcofb128v1/ref/gift128.c. The
# GIFT_RC[40] round-constant table is sized for the full count; reducing the
# loop bound simply consumes fewer entries.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the SAME archive name so
# build_cli.sh stays byte-identical to the base task.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="gift-cofb.zip"

# band|rounds|patch-file
A_VARIANTS=(
    "easy|9|variant_easy.patch"
    "medium|12|variant_medium.patch"
    "hard|14|variant_hard.patch"
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
    chmod -R u+w "$TMP" 2>/dev/null || true
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
