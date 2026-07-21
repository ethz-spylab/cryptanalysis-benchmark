#!/bin/bash
# Approach A (reduce permutation blank rounds) per
# algorithm_scaling_down/nist_sha3/round_1/Abacus.txt (+ MEDIUM_VARIANTS_ADDENDUM.md).
# Knob: Abacus/Reference Implementation/Abacus_Reference.h : NUM_BLANK_ROUNDS
#   default 135  ->  Hard 10, Medium 8, Easy 6.
#
# Deviation from the spec, recorded in
# algorithm_scaling_down/IMPLEMENTATION_NOTES.md:
#   The spec describes the original as "ROUNDS = 20" with a `#define ROUNDS R`
#   patch site. The reference implementation ships no `ROUNDS` macro; the
#   closest analog is `NUM_BLANK_ROUNDS` (default 135) — the count of blank
#   permutation iterations between absorption and squeezing. We patch
#   NUM_BLANK_ROUNDS to the spec's literal R values (10/8/6) and accept the
#   discrepancy with the spec's claimed original of 20.
#
# Concealment: patch artifacts live in ./variant_patches/ (algorithm ROOT,
# outside environment/ => never in the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays byte-identical to base.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Abacus.zip"
EXTRACT_ROOT="Abacus"   # top-level dir inside Abacus.zip; the dir patch -d resolves against

# band|NUM_BLANK_ROUNDS|patch-file
A_VARIANTS=(
    "easy|6|variant_easy.patch"
    "medium|8|variant_medium.patch"
    "hard|10|variant_hard.patch"
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
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
