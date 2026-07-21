#!/bin/bash
# Approach A (reduce NROUND1 / NROUND2) per
# algorithm_scaling_down/nist_lwc/finalists/tinyjambu.txt (+ MEDIUM addendum):
#   - Hard   (2^60-2^80): NROUND1 = 320, NROUND2 = 768
#   - Medium (2^40-2^60): NROUND1 = 256, NROUND2 = 640
#   - Easy   (2^30-2^40): NROUND1 = 224, NROUND2 = 512
# Upstream finalist v2 reference: NROUND1 = 128*5 = 640, NROUND2 = 128*8 = 1024,
# the literal `#define NROUND1 128*5` / `#define NROUND2 128*8` in
# tinyjambu/Implementations/crypto_aead/tinyjambu128v2/ref/encrypt.c.
#
# Concealment design: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent). At generation time we unzip
# the variant's own archive, apply the band patch, and repack into the SAME
# archive name, so build_cli.sh stays byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="tinyjambu.zip"
EXTRACT_ROOT="tinyjambu"   # top-level dir inside the archive; patch -d resolves here

# band|NROUND1|NROUND2|patch-file  (folder suffix encodes the real values)
A_VARIANTS=(
    "easy|224|512|variant_easy.patch"
    "medium|256|640|variant_medium.patch"
    "hard|320|768|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND N1 N2 PATCH <<< "$entry"
    SUFFIX="${BAND}_n1_${N1}_n2_${N2}"
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
