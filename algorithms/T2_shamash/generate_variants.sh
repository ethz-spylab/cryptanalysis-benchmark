#!/bin/bash
# Approach A: reduce NRINIT (init-phase rounds) per algorithm_scaling_down spec
# (nist_lwc/round_1/shamash-shamashash.txt). NRINIT must stay a multiple of
# STEP=11 for the super-round structure to align; spec values all satisfy this.
#   Hard NRINIT=88  Medium NRINIT=77  Easy NRINIT=66   (upstream full = 132)
#   NRMID / NREND left at upstream.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the same archive name so build_cli.sh
# stays byte-identical to the base task.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="shamash-shamashash.zip"
EXTRACT_ROOT="shamash-shamashash"   # top-level dir inside the archive

# band|NRINIT|patch-file
A_VARIANTS=(
    "easy|66|variant_easy.patch"
    "medium|77|variant_medium.patch"
    "hard|88|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NRINIT PATCH <<< "$entry"
    SUFFIX="${BAND}_nrinit${NRINIT}"
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
