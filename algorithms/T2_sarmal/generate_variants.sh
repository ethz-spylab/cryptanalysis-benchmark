#!/bin/bash
# Approach A (reduce ROUNDS) per
# algorithm_scaling_down/nist_sha3/round_1/Sarmal.txt and
# MEDIUM_VARIANTS_ADDENDUM.md:
#   Hard   (2^60-2^80): ROUNDS = 5
#   Medium (2^40-2^60): ROUNDS = 4
#   Easy   (2^30-2^40): ROUNDS = 3
# Upstream baseline: 8 rounds (Sarmal-256: 4 SIGMA blocks per branch × 2 branches).
#
# **Deviation from the spec.** sarmal.h has no `#define ROUNDS` — the
# compression function is fully unrolled in sarmal_ref.c::HashBlock with 4
# G() calls per SIGMA block. We treat one SIGMA block (4 G calls) as one
# round, and remove SIGMA blocks to hit the target round counts:
#
#   Hard  (5 = 3 left + 2 right): drop SIGMA3, SIGMA6, SIGMA7
#   Med   (4 = 2 left + 2 right): drop SIGMA2, SIGMA3, SIGMA6, SIGMA7
#   Easy  (3 = 1 left + 2 right): drop SIGMA1, SIGMA2, SIGMA3, SIGMA6, SIGMA7
#
# Each SIGMA block has 4 G() calls in alternating leftTemp1↔leftTemp2
# (resp. rightTemp1↔rightTemp2) form, so removing whole blocks keeps the
# state machine consistent (state always lands back in *Temp1).
#
# Concealment: the weakening lives in committed unified-diff patches under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in
# the Docker build context => invisible to the agent). At generation time we
# unzip the variant's pristine archive, apply the band patch, and repack into
# the SAME archive name, so build_cli.sh stays byte-identical to the base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Sarmal.zip"
EXTRACT_ROOT="Sarmal"   # top-level dir inside the archive; patch -d resolves here

# Format: <band>|<rounds>|<patch-file>
VARIANTS=(
    "easy|3|variant_easy.patch"
    "medium|4|variant_medium.patch"
    "hard|5|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND ROUNDS PATCH <<< "$entry"
    SUFFIX="${BAND}_r${ROUNDS}"
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
