#!/bin/bash
# HPC scaling-down variants per
#   variant_workfolder/final_fixes_recommendation.md (Section 1, "HPC")
# and the runbook's three-band rule (easy / medium / hard).
#
# Per-band design (UNCHANGED from the original generator — values, knob and
# folder names are preserved exactly; only the delivery mechanism moved):
#   - Hard   (2^60-2^80): R = 4 with key-derived spice ON
#   - Medium (2^40-2^60): R = 4 with spice forced to all-zeros
#   - Easy   (2^30-2^40): R = 3 with key-derived spice ON
#
# The recipe recovers a real medium between hard R=4 and easy R=3 by toggling
# HPC's per-round 8x64-bit "spice" mixing. The shipped reference (Brian
# Gladman's port) leaves `spice[8]` a static all-zero global, so the keyspice
# bands inject a short population in `set_key()` that copies eight 64-bit words
# from the expanded key schedule (`l_key[270..277]`) into `spice[]`, making
# spice a deterministic function of the user key. The zerospice band omits that
# population, leaving the round body's spice operations as no-ops.
#
# Concealment design (loose checked-in source — no upstream archive):
# build_cli.sh restores a fresh working copy from the committed
# environment/algorithm_src/vendor/HPC/hpc.c on every build. The weakening is
# therefore applied to that vendored copy. The per-band edits live as reviewable
# patch artifacts in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/, so they never enter the Docker build context => invisible to the
# agent). For each variant we cp the algorithm, apply the band's patch directly
# to the variant's vendored source, then delete variant_patches/ from the variant
# so no weakening artifact ships. build_cli.sh is left byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"

# Variant table: <band>|<folder-suffix>|<patch-file>
# Folder suffixes match the original generator's naming exactly.
A_VARIANTS=(
    "easy|easy_r3_keyspice|variant_easy.patch"
    "medium|medium_r4_zerospice|variant_medium.patch"
    "hard|hard_r4_keyspice|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND SUFFIX PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Apply the band's weakening patch to the variant's vendored HPC source.
    # The vendored tree root is environment/algorithm_src/vendor/, and the
    # patch paths are HPC/hpc.c, so strip level 1 against that dir.
    patch -p1 -d "$VARIANT_DIR/$SRC_REL/vendor" < "$SCRIPT_DIR/variant_patches/$PATCH"

    # Drop the patch artifacts from the shipped variant.
    rm -rf "$VARIANT_DIR/variant_patches"
done
