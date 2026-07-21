#!/bin/bash
# SAEAES scaling-down variants (Approach A: truncate AesEnc to R rounds).
#
# The reference's `AesEnc()` in aes.c (saeaes128a120t128v1/ref) is fully
# unrolled, with 9 SM/RK pairs followed by a final SS/RK at offset 40 (in the
# active CRYPTO_KEYBYTES==16 block). The unroll alternates state buffers:
# SM(S,T) ... SM(T,S) ... — after k SMs the value lives in T iff k is odd.
# The final SS(T,S) requires the preceding chain to end in T, so even R values
# (R=4, R=6) are parity-clean as-is; odd R (R=5) needs the closing chain flipped
# to SS(S,T);RK(T,...);PutU32(T,...). See variant_workfolder/final_fixes_
# recommendation.md (SAEAES recipe).
#
# Spec values: hard=R6, medium=R5, easy=R4.
#
# Mechanism: generation-time patch + repack. The weakening edits live as
# committed unified-diff patches in ./variant_patches/ (algorithm ROOT, a
# sibling of environment/ => never in the Docker build context => invisible to
# the agent). For each band we copy the algorithm, unzip the variant's archive
# to a temp dir, apply the band patch to the extracted aes.c, and repack into
# the SAME archive name so build_cli.sh stays byte-identical to base. The
# committed original archive is never modified.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="saeaes.zip"

# suffix | patch file
VARIANTS=(
    "hard_r6|variant_hard_r6.patch"
    "medium_r5|variant_medium_r5.patch"
    "easy_r4|variant_easy_r4.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r SUFFIX PATCH <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    # Patch paths are saeaes/... relative; unzip yields $TMP/saeaes/..., so -p1
    # (strip the leading a/ or b/) applied at $TMP resolves correctly.
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
