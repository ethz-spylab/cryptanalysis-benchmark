#!/bin/bash
# Approach A: reduce ExternalRounds256 in SHAvite3-256.h (the cli's default
# hashbitlen=256 routes through the 256-bit core), per spec values from
# nist_sha3/round_2/SHAvite-3_Round2.txt (per-round gain ~2^20):
#   Hard (2^60-2^80) R=6   Medium (2^40-2^60) R=5   Easy (2^30-2^40) R=4
#
# Implementation note: ExpandedMessageSize256 is normally
#   (ExternalRounds256*4*InternalRounds256) = 144, and MessageExpansion256
# hardcodes writes up to rk[143]. Just reducing ExternalRounds256 would
# shrink the rk[] array and overflow the expansion. We therefore decouple the
# two: pin ExpandedMessageSize256 = 144 (full upstream) so the expansion still
# fits, and only reduce the encryption-loop bound. The expansion produces
# extra unused round keys, but that's harmless.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).
# The weakened source is repacked into the SAME archive name so build_cli.sh
# stays byte-identical to base.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="CODE_KAT_SHAvite.zip"

# band|param-encoding|patch-file
A_VARIANTS=(
    "easy|r4|variant_easy.patch"
    "medium|r5|variant_medium.patch"
    "hard|r6|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    # Archive extracts Reference_Implementation/ at its root => patch -p1 -d "$TMP".
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
