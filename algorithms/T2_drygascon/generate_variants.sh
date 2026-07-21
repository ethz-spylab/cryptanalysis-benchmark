#!/bin/bash
# Approach A (reduce DRYSPONGE_ROUNDS / DRYSPONGE_INIT_ROUNDS) per
#   algorithm_scaling_down/nist_lwc/round_2/drygascon.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (hard=6, medium=5, easy=4 + init=6).
#
# Concealment design: the weakening is applied at GENERATION time by
# unzipping the vendored upstream archive, applying a committed patch from
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in
# the Docker build context => invisible to the agent), and repacking into the
# SAME archive name. build_cli.sh stays byte-identical to base — it just
# untars whatever archive ships in the variant.
#
# Knob: drysponge.h:
#   DRYSPONGE_ROUNDS       default (8-1)=7  -> hard 6, medium 5, easy 4
#   DRYSPONGE_INIT_ROUNDS  default (12-1)=11 -> easy 6 (others keep 11)
# The patched header lives at
#   DryGASCON/Implementations/crypto_aead/drygascon128k32/ref/drysponge.h
# which build_cli.sh's REFDIR copies alongside cli.c.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="vendored-DryGASCON.tar.gz"
EXTRACT_ROOT="DryGASCON"   # top-level dir inside the archive; patch -d resolves against it

# Format: <band>|<DRYSPONGE_ROUNDS>|<DRYSPONGE_INIT_ROUNDS>|<patch-file>
A_VARIANTS=(
    "easy|4|6|variant_easy.patch"
    "medium|5|11|variant_medium.patch"
    "hard|6|11|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R IR PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}_init${IR}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    tar xzf "$ARCH" -C "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    rm -f "$ARCH"
    tar czf "$ARCH" -C "$TMP" "$EXTRACT_ROOT"
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
