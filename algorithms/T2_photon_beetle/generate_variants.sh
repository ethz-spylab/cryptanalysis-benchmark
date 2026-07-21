#!/bin/bash
# Approach A (reduce ROUND of the PHOTON_256 permutation) per the spec +
# MEDIUM_VARIANTS_ADDENDUM.md. Three security bands:
#   - Hard   (2^60–2^80): ROUND = 7
#   - Medium (2^40–2^60): ROUND = 6
#   - Easy   (2^30–2^40): ROUND = 5
#
# Concealment design (generation-time patch + repack): the weakening edit is
# kept in committed patch artifacts under ./variant_patches/ (algorithm ROOT,
# a sibling of environment/ => never enters the Docker build context =>
# invisible to the agent). For each variant we unzip the vendored archive,
# apply the band patch to the extracted source, and repack into the SAME
# archive name so build_cli.sh stays byte-identical to the base task.
#
# RC[D][12] is sized for 12 rounds; reducing ROUND never under-runs the
# round-constants table.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="photon-beetle.zip"
# Top-level dir inside the archive; the patch -d resolves the patched file
# path (Implementations/.../ref/photon.h) against this.
EXTRACT_ROOT="photon-beetle"

# band|round|patch-file
A_VARIANTS=(
    "easy|5|variant_easy.patch"
    "medium|6|variant_medium.patch"
    "hard|7|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_round${R}"
    if [[ "$BAND" == "medium" ]]; then
        # Reorder the suffix for the medium variant only: with
        # "medium_round6" the directory name has "_" at char 32, and
        # Harbor's 32-char trial-name truncation + "__" join produces
        # "___" — invalid per https://github.com/distribution/reference
        # image-ref grammar. Putting "round_" before the band shifts the
        # band to a later position so char 32 lands inside "medium". Both
        # "_variant_" and "_medium_" substrings remain present for
        # filtering.
        SUFFIX="round_${BAND}_${R}"
    fi
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

    # Remove the patch artifacts from the variant so they never enter the
    # Docker build context.
    rm -rf "$VARIANT_DIR/variant_patches"
done
