#!/bin/bash
# Approach B (numMPCRounds = T) per
# variant_workfolder/final_fixes_recommendation.md ("Picnic"). Approach A
# (reduce LowMC `numRounds`) is blocked by the implementation: Picnic v6.0's
# `createRandomTape` rejects tapes shorter than `digestSizeBytes` (= 32 for
# L1_FS), forcing R >= 9 — well above the spec's A-band targets. Approach B
# is the spec's recommended path for Picnic R3 and is adopted here as a
# documented exception to the runbook's A-only rule.
#
# T (= paramset->numMPCRounds) drives the soundness error of Picnic's
# Fiat-Shamir signature: forgery probability ~ (3/4)^T, so attacker work
# ~ (4/3)^T. Bands:
#   Hard   (~2^60-2^80): T = 100
#   Medium (~2^40-2^60): T =  70
#   Easy   (~2^30-2^40): T =  45
#
# Patch site: paramset->numMPCRounds = 219 in Picnic-6.0/picnic.c (the
# L1_FS/L1_UR case used by cli.c, and the L1_full case — both "= 219"
# assignments, matching the original injection sed which rewrote every line).
#
# Concealment: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in
# the Docker build context => invisible to the agent). The weakened source is
# repacked into the same archive name, so build_cli.sh stays byte-identical
# to base — no build-time injection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="picnic-v6.0.tar.gz"
EXTRACT_ROOT="Picnic-6.0"   # the dir the patch -p1 -d resolves against

# Format: <band>|<T>|<patch-file>
B_VARIANTS=(
    "easy|45|variant_easy.patch"
    "medium|70|variant_medium.patch"
    "hard|100|variant_hard.patch"
)

for entry in "${B_VARIANTS[@]}"; do
    IFS='|' read -r BAND T PATCH <<< "$entry"
    SUFFIX="b_${BAND}_t${T}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

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
