#!/bin/bash
# Approach A (reduce CORE_ROUNDS) per
# algorithm_scaling_down/nist_aes/round_2_finalists/MARS.txt + addendum.
#   Hard   (2^60-2^80): CORE_ROUNDS = 3
#   Medium (2^40-2^60): CORE_ROUNDS = 2
#   Easy   (2^30-2^40): CORE_ROUNDS = 1
# The reference has no `#define CORE_ROUNDS`; the count is the literal `16`
# in two loops (`for (i = 0; i < 16; i++)` in mars_encrypt and
# `for (i = 15; i >= 0; i--)` in mars_decrypt) of Mars/mars-ref.c. The
# forward/backward split at `i<8` / `i>=8` is never reached for R<=8: encrypt
# runs all-forward and decrypt runs all-backward, and the dst-index relabelling
# between encrypt and decrypt makes those two modes mutual inverses, so
# round-trip succeeds for any R. Mixing rounds (8+8) and key schedule
# (NUM_SETUP=7, NUM_ROUNDS=16 round keys) are left at upstream.
#
# Concealment design: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in the
# Docker build context => invisible to the agent). The archive is unpacked,
# the weakened source repacked into the SAME archive name, and build_cli.sh is
# left byte-identical to base. The committed original archive is never touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Mars-AES-2.zip"        # outer zip
INNER_TAR="mars-dos-refc.tar"   # tar inside the zip that build_cli.sh extracts
EXTRACT_ROOT="Mars"             # top-level dir inside the inner tar

# band|CORE_ROUNDS|decrement-loop-start|patch-file
A_VARIANTS=(
    "easy|1|0|variant_easy.patch"
    "medium|2|1|variant_medium.patch"
    "hard|3|2|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R DEC_HI PATCH <<< "$entry"
    SUFFIX="${BAND}_core${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"

    # Unpack the outer zip (yields the four .tar members).
    unzip -q -o "$ARCH" -d "$TMP/zip"
    # Unpack only the reference-C tar that build_cli.sh consumes.
    mkdir -p "$TMP/tar"
    tar -xf "$TMP/zip/$INNER_TAR" -C "$TMP/tar"

    # Apply the band weakening to the extracted reference source.
    patch -p1 -d "$TMP/tar" < "$SCRIPT_DIR/variant_patches/$PATCH"

    # Repack the inner tar (same top dir => build_cli.sh stays pristine).
    rm -f "$TMP/zip/$INNER_TAR"
    ( cd "$TMP/tar" && tar -cf "$TMP/zip/$INNER_TAR" "$EXTRACT_ROOT" )

    # Repack the outer zip into the SAME archive name.
    rm -f "$ARCH"
    ( cd "$TMP/zip" && zip -q -r -X "$ARCH" . )

    rm -rf "$TMP"
    rm -rf "$VARIANT_DIR/variant_patches"
done
