#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Skein_FinalRnd.zip"
EXTRACT_ROOT="Skein_FinalRnd"   # top-level dir inside the archive; patch -d resolves against it

# Approach A: round-reduce Threefish.
# The cli defaults to hashbitlen=256. In SHA3api_ref.c the Skein-256
# branch is guarded by `#if SKEIN_256_NIST_MAX_HASH_BITS`, a macro that
# is never defined (only SKEIN_256_NIST_MAX_HASHBITS=0 exists), so that
# branch is compiled out and a 256-bit digest (<= SKEIN_512_NIST_MAX_HASHBITS
# = 512) is actually produced by Skein_512_Init, i.e. Skein-512-256.
# The governing round constant for the default output path is therefore
# SKEIN_512_ROUNDS_TOTAL (baseline 72), NOT SKEIN_256_ROUNDS_TOTAL.
# The per-band patches reduce BOTH SKEIN_256_ROUNDS_TOTAL and
# SKEIN_512_ROUNDS_TOTAL in Reference_Implementation/skein.h to the band
# value; the SKEIN_512 edit is the one that changes the graded digest
# (verified empirically: each band's 256-bit digest differs from the
# unmodified base and from the other bands). The skein_block.c 512 loop
# iterates SKEIN_512_ROUNDS_TOTAL/8 times, so the count must stay a
# multiple of 8 (same constraint as the 256 path).
#
# Spec values from Skein_FinalRnd.txt (per-round gain ~2^4–2^6):
#   - Hard   (2^60–2^80): ROUNDS = 24
#   - Medium (2^40–2^60): ROUNDS = 19
#   - Easy   (2^30–2^40): ROUNDS = 14
#
# Implementation constraint: skein_block.c iterates
#   for (r=1; r <= SKEIN_512_ROUNDS_TOTAL/8; r++)   (default path)
# and each iteration does 8 rounds inline. Round count must therefore
# be a multiple of 8. We use the closest multiples of 8 to the spec:
#   - Hard:   24 (= spec)
#   - Medium: 16 (spec 19; -3 rounds, ~2^12–2^18 cheaper, still ≈ band)
#   - Easy:    8 (spec 14; -6 rounds, drops below easy band)
# Recorded in algorithm_scaling_down/IMPLEMENTATION_NOTES.md.
#
# Concealment: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, outside environment/ => never in
# the Docker build context => invisible to the agent). The patched
# source is repacked into the same archive name so build_cli.sh stays
# byte-identical to base.
#
# Format: <band>|<R>|<patch-file>
A_VARIANTS=(
    "easy|8|variant_easy_r8.patch"
    "medium|16|variant_medium_r16.patch"
    "hard|24|variant_hard_r24.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    chmod -R u+w "$TMP/$EXTRACT_ROOT"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" "$EXTRACT_ROOT" )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
