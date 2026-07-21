#!/bin/bash
# Approach A (round-reduce CRYPTO_NBROUNDS_AFTER on the AFTER-fork branches).
# Three security bands per the round-2 spec + addendum:
#   - Hard   (2^60-2^80): CRYPTO_NBROUNDS_AFTER = 13
#   - Medium (2^40-2^60): CRYPTO_NBROUNDS_AFTER = 10
#   - Easy   (2^30-2^40): CRYPTO_NBROUNDS_AFTER =  8
#
# CRYPTO_NBROUNDS_BEFORE is kept at the upstream value to preserve the
# forking structure. The shipped reference is paefforkskinnyb128t288n104v1
# (BEFORE=25, AFTER=31); the round-constant table holds 87 entries, so any
# AFTER <= 62 compiles cleanly. Mode A: extra_api.h ships only inside the
# upstream zip, so we patch it after unzip.
#
# Concealment: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in
# the Docker build context => invisible to the agent). At generation time we
# unzip the variant's forkae.zip, apply the band patch, and repack into the
# SAME archive name so build_cli.sh stays byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="forkae.zip"
EXTRACT_ROOT="forkae"   # top-level dir inside the archive; patch -d resolves against it

# band|rounds-encoding|patch-file
A_VARIANTS=(
    "easy|8|variant_easy.patch"
    "medium|10|variant_medium.patch"
    "hard|13|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ROUNDS PATCH <<< "$entry"
    SUFFIX="${BAND}_after${ROUNDS}"
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
