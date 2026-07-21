#!/bin/bash
# Serpent scaling-down variants (Approach A: reduce ROUNDS).
#
# serpent-api.h declares `#define r 32`, used uniformly by encrypt/decrypt
# loops, the keySchedule typedef (sized r+1), and the key schedule itself.
# Two literal `33`s in the key-schedule loops in serpent-ref.c have to be
# replaced with `r+1` or stack-smashing into the now-smaller K[r+1][...]
# array follows.
#
# Mechanism: generation-time patch + repack. Per band we copy the algorithm,
# unzip the variant's archive, extract the inner reference tar, apply the
# committed patch from ./variant_patches/ to the extracted source, repack the
# tar back into the SAME archive name, and drop the patch artifacts. build_cli.sh
# stays byte-identical to base; the patch artifacts live at the algorithm ROOT
# (outside environment/ => never in the Docker build context => invisible to the
# agent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="Serp-AES-2.zip"
INNER_TAR="serpent-dos-refc.tar"   # the reference tar build_cli.sh extracts
EXTRACT_ROOT="Serpent"             # top-level dir inside INNER_TAR

# suffix | rounds | patch-file
VARIANTS=(
    "hard_r8|8|variant_hard.patch"
    "medium_r6|6|variant_medium.patch"
    "easy_r5|5|variant_easy.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r SUFFIX R PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"

    # 1) unzip variant archive -> inner tars
    unzip -q -o "$ARCH" -d "$TMP/z"
    # 2) extract reference tar -> $TMP/ex/Serpent/...
    mkdir -p "$TMP/ex"
    tar -xf "$TMP/z/$INNER_TAR" -C "$TMP/ex"
    # 3) apply the weakening patch to the extracted source
    patch -p1 -d "$TMP/ex" < "$SCRIPT_DIR/variant_patches/$PATCH"
    # 4) repack the reference tar (same internal layout) ...
    ( cd "$TMP/ex" && tar -cf "$TMP/z/$INNER_TAR" "$EXTRACT_ROOT" )
    # 5) ... and repack the zip into the SAME archive name
    rm -f "$ARCH"
    ( cd "$TMP/z" && zip -q -r -X "$ARCH" . )

    rm -rf "$TMP"
    rm -rf "$VARIANT_DIR/variant_patches"
done
