#!/bin/bash
# Approach A (reduce ROUNDS) per
# algorithm_scaling_down/nist_aes/round_2_finalists/Twofish.txt +
# MEDIUM_VARIANTS_ADDENDUM.md:
#   - Hard   (2^60-2^80): ROUNDS_128 = 4
#   - Medium (2^40-2^60): ROUNDS_128 = 3  (odd R: also needs the parity-fix
#                                          patch so encrypt/decrypt stay
#                                          inverses — patch_twofish_medium.py)
#   - Easy   (2^30-2^40): ROUNDS_128 = 2
#
# Knob: Twofish/AES.H `#define ROUNDS_128 16` (consumed by makeKey via
# numRounds[]; TOTAL_SUBKEYS uses MAX_ROUNDS=16 so the subkey buffer is always
# sized for the maximum and reducing the default scales the cipher cleanly).
#
# Concealment: the weakening patch artifacts live in ./variant_patches/ at the
# algorithm ROOT (a sibling of environment/), so they never enter the Docker
# build context and are invisible to the agent. The weakened source is patched
# at generation time and repacked into the SAME archive name, so build_cli.sh
# stays byte-identical to base. The committed original archive is never touched
# (we only ever unzip/patch/repack the per-VARIANT copy).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="2fsh-AES-2.zip"
# build_cli.sh uses this tar member inside the zip; it expands to a top-level
# "Twofish/" dir (the patch -p1 -d target).
TAR_MEMBER="twofish-dos-refc.tar"
EXTRACT_ROOT="Twofish"

# band|ROUNDS|odd-R?(yes|no)|rounds-patch
A_VARIANTS=(
    "easy|2|no|variant_easy.patch"
    "medium|3|yes|variant_medium.patch"
    "hard|4|no|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R ODD PATCH <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    # zip -> tars; extract only the ref-C tar, patch its Twofish/ tree.
    unzip -q -o "$ARCH" -d "$TMP"
    tar -xf "$TMP/$TAR_MEMBER" -C "$TMP"

    # 1. Reduce ROUNDS_128 in AES.H.
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    # 2. Odd-R parity fix in TWOFISH.C (medium only).
    if [ "$ODD" = "yes" ]; then
        python3 "$SCRIPT_DIR/variant_patches/patch_twofish_medium.py" \
            "$TMP/$EXTRACT_ROOT/TWOFISH.C"
    fi

    # Repack the patched tree into the SAME tar member, then re-zip all tars
    # back into the SAME archive name build_cli.sh expects.
    ( cd "$TMP" && rm -f "$TAR_MEMBER" && tar -cf "$TAR_MEMBER" "$EXTRACT_ROOT" )
    rm -rf "$TMP/$EXTRACT_ROOT"
    rm -f "$ARCH"
    ( cd "$TMP" && zip -q -X "$ARCH" *.tar )
    rm -rf "$TMP"

    # Drop the patch artifacts from the variant so nothing weakening-related
    # ships under environment/ (they were never in environment/ anyway, but the
    # cp -r copied the root variant_patches/ dir into the variant root).
    rm -rf "$VARIANT_DIR/variant_patches"
done
