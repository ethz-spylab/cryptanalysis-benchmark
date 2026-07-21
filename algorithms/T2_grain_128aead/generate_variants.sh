#!/bin/bash
# Approach A: reduce INIT_ROUNDS (the grain init register-skip count). Spec
# (algorithm_scaling_down/nist_lwc/finalists/grain-128aead.txt) + addendum.
# Upstream finalist v2 baseline: 320 init rounds (literal `320` in
# Implementations/crypto_aead/grain128aeadv2/ref/grain128aead-v2.c, in the
# `for (int i = 0; i < 320; i++)` loop of init_grain).
#   - Hard   (2^60-2^80): INIT_ROUNDS = 160
#   - Medium (2^40-2^60): INIT_ROUNDS = 145
#   - Easy   (2^30-2^40): INIT_ROUNDS = 130
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same archive name so build_cli.sh
# stays byte-identical to base (no build-time injection).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="grain-128aead.zip"
EXTRACT_ROOT="grain-128aead"   # top-level dir inside the archive

# band|init-rounds|patch-file
A_VARIANTS=(
    "easy|130|variant_easy.patch"
    "medium|145|variant_medium.patch"
    "hard|160|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_init${R}"
    if [[ "$BAND" == "medium" ]]; then
        # Reorder the suffix for the medium variant only: with
        # "medium_init145" the directory name has "_" at char 32, and
        # Harbor's 32-char trial-name truncation + "__" join produces
        # "___" — invalid per https://github.com/distribution/reference
        # image-ref grammar. Putting "init_" before the band shifts the
        # band to a later position so char 32 lands inside "medium". Both
        # "_variant_" and "_medium_" substrings remain present for
        # filtering.
        SUFFIX="init_${BAND}_${R}"
    fi
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Patch + repack the variant's own archive copy (never the committed base).
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Strip the patch artifacts from the variant so they never ship in the image.
    rm -rf "$VARIANT_DIR/variant_patches"
done
