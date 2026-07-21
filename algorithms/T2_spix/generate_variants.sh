#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="spix.zip"
EXTRACT_ROOT="spix"   # top-level dir inside spix.zip; the dir patch -p1 resolves against

# Approach A (reduce NUMSTEPS). Per algorithm_scaling_down/nist_lwc/round_2/
# spix.txt + MEDIUM_VARIANTS_ADDENDUM.md:
#   - Hard   (2^60–2^80): NUMSTEPS = 7
#   - Medium (2^40–2^60): NUMSTEPS = 6 (from addendum)
#   - Easy   (2^30–2^40): NUMSTEPS = 5
#
# Upstream sliscp_light256.h declares two step counts:
#   #define NUMSTEPSR9   9   // 9-step variant (used in absorb/squeeze stages)
#   #define NUMSTEPSR18  18  // 18-step variant (the AEAD's outer permutation)
# The spec's "NUMSTEPS = 18" maps to NUMSTEPSR18; the round-constant tables
# RC1_256/RC2_256/SC1_256/SC2_256 are sized for 18 entries, so any reduction
# is safe (no overrun). NUMSTEPSR9 is left at upstream so the half-step
# variant remains usable in stages that call it.
#
# Concealment design: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent). Each variant's source archive
# is unpacked, patched, and repacked into the SAME archive name so build_cli.sh
# stays byte-identical to base.
#
# Approach B and C are intentionally not implemented (policy: A only).

# band|numsteps|patch-file
A_VARIANTS=(
    "easy|5|variant_easy.patch"
    "medium|6|variant_medium.patch"
    "hard|7|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NUMSTEPS PATCH <<< "$entry"
    SUFFIX="${BAND}_numsteps${NUMSTEPS}"
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
