#!/bin/bash
# Approach A (reduce ROUNDS). Three security bands:
#   - Hard   (2^60–2^80): R = 16 (full, unmodified — Knudsen–Rijmen ~2^60)
#                         from algorithm_scaling_down/nist_aes/round_1/LOKI97.txt
#   - Medium (2^40–2^60): R = 14  — from MEDIUM_VARIANTS_ADDENDUM.md
#   - Easy   (2^30–2^40): R = 12  — from algorithm_scaling_down/nist_aes/round_1/LOKI97.txt
#
# Mode: generation-time patch + repack. The reference header cref/loki97.h
# defines `#define ROUNDS 16` and `#define NUM_SUBKEYS 3*ROUNDS`, so reducing
# ROUNDS automatically scales the subkey count — no other patch needed. Each
# band's edit is committed as a unified-diff patch under ./variant_patches/
# (algorithm ROOT, a sibling of environment/, so it never enters the Docker
# build context and is invisible to the agent). The patch is applied to a
# fresh extraction of LOKI97-2.zip and the weakened source is repacked into the
# same archive name, so build_cli.sh stays byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LOKI97-2.zip"
EXTRACT_ROOT="."   # the zip contains cref/ at its top level

# band|param-encoding|patch-file   (empty patch-file => unmodified full strength)
A_VARIANTS=(
    "easy|r12|variant_easy.patch"
    "medium|r14|variant_medium.patch"
    "hard|r16|"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Hard band uses upstream R=16 unmodified — no patch, no repack.
    if [ -n "$PATCH" ]; then
        ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
        TMP="$(mktemp -d)"
        unzip -q -o "$ARCH" -d "$TMP"
        patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
        ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
        rm -rf "$TMP"
    fi

    rm -rf "$VARIANT_DIR/variant_patches"
done
