#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Reference_Implementation.2024.10.10.1.zip"
EXTRACT_ROOT="Reference_Implementation"   # top-level dir inside the archive; patch -d resolves against it

# Approach A (reduce r). Three security bands per the spec + addendum:
#   - Hard   (2^60–2^80): r=5003, t=66        — from BIKE-Round4.txt
#   - Medium (2^40–2^60): r=3500, t=49        — from MEDIUM_VARIANTS_ADDENDUM.md
#   - Easy   (2^30–2^40): r=2503, t=33        — from BIKE-Round4.txt
#
# Three deviations from the spec, recorded in
# algorithm_scaling_down/IMPLEMENTATION_NOTES.md:
#   1. DV is scaled proportionally with r (DV/r ≈ 0.58%) rather than held at
#      71. Holding DV constant breaks the BGF decoder (every honest decap
#      fails).
#   2. DV must be odd. Even DV makes the secret polynomial evaluate to 0 at
#      x=1, so (x-1) divides it and it is not coprime to x^r-1 — NTL aborts
#      with "InvMod: inverse undefined" during keypair generation. BIKE's
#      official Level-1/3/5 values DV = 71, 103, 137 are all odd. We pick
#      the closest odd to the density target: 29 (hard), 21 (medium),
#      17 (easy).
#   3. r values are replaced where the spec value doesn't admit a working
#      polynomial ring inversion in the reference implementation:
#        easy:   2503 -> 3001  (2503: NTL "InvMod: inverse undefined")
#        medium: 3500 -> 3499  (3500 isn't prime; 3499 is the closest prime)
#        hard:   5003 -> 5003  (already works)
#
# Approach B and C are intentionally not implemented (policy: A only).
#
# Generation-time repack: the weakened defs.h values live in committed patch
# artifacts under ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enters the Docker build context => invisible to the
# agent). For each variant we unzip the variant's copy of the archive, apply
# the band patch, and repack into the SAME archive name, so build_cli.sh is
# left byte-identical to base.
#
# Format: <band>|<R_BITS>|<DV>|<T1>|<patch-file>
A_VARIANTS=(
    "easy|3001|17|33|variant_easy.patch"
    "medium|3499|21|49|variant_medium.patch"
    "hard|5003|29|66|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R_BITS DV T1 PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R_BITS}_dv${DV}_t${T1}"
    if [[ "$BAND" == "easy" || "$BAND" == "hard" ]]; then
        # Drop the "_" before t<T1> for the easy/hard variants only: with
        # the underscore, their directory name has "_" at char 32, and
        # Harbor's 32-char trial-name truncation + "__" join produces
        # "___" — invalid per https://github.com/distribution/reference
        # image-ref grammar. (Medium has a longer band name and isn't
        # affected, so it keeps the original layout.)
        SUFFIX="${BAND}_r${R_BITS}_dv${DV}t${T1}"
    fi
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Patch the variant's own archive copy, then repack into the same name so
    # build_cli.sh stays pristine. NEVER touch $SCRIPT_DIR's archive.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Drop the patch artifacts from the variant so nothing weakening-related
    # ships in the task folder.
    rm -rf "$VARIANT_DIR/variant_patches"
done
