#!/bin/bash
# Approach A: reduce N_RNDS in skinny_reference.c (Romulus-N / SKINNY-128-384+).
# Bands per algorithm_scaling_down/nist_lwc/finalists/romulus.txt + addendum:
#   Hard (2^60-2^80): N_RNDS = 14
#   Medium (2^40-2^60): N_RNDS = 12
#   Easy (2^30-2^40): N_RNDS = 11
# Upstream baseline: N_RNDS = 40 (SKINNY-128-384+).
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside environment/
# => never enters the Docker build context => invisible to the agent). The weakened
# source is repacked into the same vendored archive name so build_cli.sh stays
# byte-identical to the base task.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="vendored-romulus.tar.gz"
EXTRACT_ROOT="romulus"   # top-level dir inside the archive; the dir `patch -d` resolves against

# band|param-encoding|patch-file
A_VARIANTS=(
    "easy|r11|variant_easy.patch"
    "medium|r12|variant_medium.patch"
    "hard|r14|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    tar xzf "$ARCH" -C "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && tar czf "$ARCH" "$EXTRACT_ROOT" )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
