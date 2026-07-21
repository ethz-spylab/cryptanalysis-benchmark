#!/bin/bash
# Approach A (reduce ISAP_sE) per
# algorithm_scaling_down/nist_lwc/finalists/isap.txt and
# MEDIUM_VARIANTS_ADDENDUM.md (isap row).
# Upstream finalist isapa128av20 ref ships `#define ISAP_sE 6` in isap.h
# (note: the round_2 spec text references sE=12; the leakage-aware finalist
# update reduced sE to 6). We further reduce sE per the band:
#   Hard   (2^60-2^80): ISAP_sE = 5
#   Medium (2^40-2^60): ISAP_sE = 4
#   Easy   (2^30-2^40): ISAP_sE = 3
# sH/sB/sK are left at their upstream values (12/1/12).
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enter the Docker build context => invisible to the
# agent). isap.h ships inside the upstream isap.zip, so we unzip the variant's
# archive at generation time, apply the band's patch, and repack into the same
# archive name. build_cli.sh stays byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="isap.zip"
# Top-level dir inside isap.zip; the patch paths (a/isap/...) resolve under
# $TMP, so we apply with `patch -p1 -d "$TMP"`.
EXTRACT_ROOT="isap"

# band|sE-value|patch-file
VARIANTS=(
    "easy|3|variant_easy.patch"
    "medium|4|variant_medium.patch"
    "hard|5|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND SE PATCH <<< "$entry"
    SUFFIX="${BAND}_se${SE}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
