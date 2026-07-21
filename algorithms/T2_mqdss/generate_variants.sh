#!/bin/bash
# Approach A (reduce N = M, the MQ system size) per
# algorithm_scaling_down/nist_pqc/round_2/MQDSS-Round2.txt and
# MEDIUM_VARIANTS_ADDENDUM.md.  Knob: Reference_Implementation params.h
# `#define N 48` -> hard N=24, medium N=16, easy N=8.
#
# **Deviation from the spec.** The reference implementation hard-codes the
# assumption that N is a multiple of 8 — it packs 5-bit GF(31) elements with
# `NPACKED_BYTES = (N*5) >> 3` (floor), but `gf31_npack` always writes
# ceil(5N/8) bytes. When N is not a multiple of 8, sign/verify do
# `memcpy(buf, packbuf, NPACKED_BYTES*ROUNDS)` reading more bytes than the
# packed output actually fills, producing memory corruption / segfaults.
# Rather than rewrite the upstream packer, we pick N values that *are*
# multiples of 8, which keeps floor==ceil and the upstream code intact:
#   Hard   (~2^60-2^80): N = M = 24 (~2^72)  [spec 28, ~2^84 — too high]
#   Medium (~2^40-2^60): N = M = 16 (~2^48)  [spec 20]
#   Easy   (~2^30-2^40): N = M =  8 (~2^24)  [spec 14, ~2^42]
# See IMPLEMENTATION_NOTES.md for details.
#
# Concealment: the weakening lives in committed unified-diff patches under
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in the
# Docker build context => invisible to the agent). For each variant the
# archive is unzipped, patched, and repacked into the SAME archive name, so
# build_cli.sh ends up byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="MQDSS-Round2.zip"
EXTRACT_ROOT="NIST-PQ-Submission-MQDSS-20190315"

# band|N|patch-file
VARIANTS=(
    "easy|8|variant_easy.patch"
    "medium|16|variant_medium.patch"
    "hard|24|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND N PATCH <<< "$entry"
    SUFFIX="${BAND}_n${N}"
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
