#!/bin/bash
# SWIFFTX scaling-down variants (Approach A: reduce FFT dimension N).
#
# Per `variant_workfolder/final_fixes_recommendation.md` § SWIFFTX we drive
# all coupled artefacts (N, LOGN, OMEGA, SWIFFTX_OUTPUT_BLOCK_SIZE, HAIFA_IV
# tables) from the chosen N. The recipe's "regenerate As / HAIFA_IV from the
# spec's PI-digit and iterated-compression seeds" is implemented as a
# slice of the upstream tables: both serve as deterministic constant byte
# sources, and an attacker computing the reduced SWIFFTX sees the same
# constants we do — which is the property the benchmark needs. OMEGA is
# recomputed exactly (primitive 2N-th root of unity in Z_257; we use
# 42^(64/N) mod 257 since the upstream OMEGA = 42 has order 128).
#
#   Hard   (2^60–2^80): N=32, LOGN=5, OMEGA=222 (= 42^2 mod 257)
#   Medium (2^40–2^60): N=16, LOGN=4, OMEGA=197 (= 42^4 mod 257)
#   Easy   (2^30–2^40): N=8,  LOGN=3, OMEGA=2   (= 42^8 mod 257)
#
# Concealment: the weakening helper (patch_swifftx.py) lives in ./variant_patches/
# at the algorithm ROOT — a sibling of environment/, so it never enters the Docker
# build context. The weakened source is patched and repacked into the same archive
# name (SWIFFTX.zip), so build_cli.sh stays byte-identical to the base task.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="SWIFFTX.zip"
# The reference-implementation sources patched by build_cli.sh's `cp` step live
# under this directory inside the archive.
REF_DIR="SWIFFTX/Reference Implementation"

# <band>|<N>|<LOGN>|<OMEGA>
A_VARIANTS=(
    "easy|8|3|2"
    "medium|16|4|197"
    "hard|32|5|222"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND N LOGN OMEGA <<< "$entry"
    SUFFIX="${BAND}_n${N}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    python3 "$SCRIPT_DIR/variant_patches/patch_swifftx.py" "$N" "$LOGN" "$OMEGA" \
        "$TMP/$REF_DIR/SWIFFTX.c" \
        "$TMP/$REF_DIR/SHA3.h" \
        "$TMP/$REF_DIR/SHA3.c"

    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
