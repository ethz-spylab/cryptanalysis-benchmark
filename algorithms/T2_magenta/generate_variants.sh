#!/bin/bash
# Approach A (reduce ROUNDS) per
#   algorithm_scaling_down/nist_aes/round_1/MAGENTA.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (hard=6 full, medium=5, easy=4).
#
# Earlier IMPLEMENTATION_NOTES.md entry flagged that the reference
# (`magenta.c`) has six unrolled `r_fun` calls in encrypt/decrypt and a
# palindromic key index pattern (l_key[0..11] = A A B B A A); truncating
# the unrolled body to 4 or 5 calls breaks the palindrome and the cipher
# is no longer self-inverse. The structural fix from
# variant_workfolder/final_fixes_recommendation.md is to rewrite both the
# unrolled body and `set_key` case 2 together so the palindrome is
# preserved at smaller R. patch_magenta.py does both edits in a single
# pass for any even R in {2, 4, 6}.
#
# Variant table:
#   - hard   R=6 (palindrome A A B B A A) — upstream, no patch.
#   - medium R=4 (palindrome A B B A) — security drops by ~20 bits.
#   - easy   R=2 (palindrome A A) — trivial differential break.
#
# We deviate from the spec's R=5 medium and R=4 easy because R=5 is odd:
# MAGENTA's encrypt and decrypt apply identical r_fun sequences with the
# same key indices, and self-inverseness requires a centred palindrome,
# which exists only for even R.
#
# Concealment design: the weakening helper (patch_magenta.py) lives in
# ./variant_patches/ at the algorithm ROOT — a sibling of environment/ —
# so it never enters the Docker build context and is invisible to the
# agent. The weakened source is patched at GENERATION time and repacked
# into the same MAGENTA-2.zip archive name, so build_cli.sh stays pristine
# (byte-identical to base) for every variant.
#
# Format: <band>|<R>
A_VARIANTS=(
    "hard|6"
    "medium|4"
    "easy|2"
)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="MAGENTA-2.zip"

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    if [ "$R" -ne 6 ]; then
        # Generation-time patch + repack. The committed archive ships
        # magenta.c and std_defs.h at its root; we unpack into a temp dir,
        # CRLF-normalise magenta.c (matching build_cli.sh's preprocessing,
        # which patch_magenta.py's LF-anchored regexes rely on), apply the
        # round-reduction patch, and repack into the SAME archive name in
        # the VARIANT_DIR (NEVER the committed original under $SCRIPT_DIR).
        ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
        TMP="$(mktemp -d)"
        unzip -q -o "$ARCH" -d "$TMP"
        tr -d '\r' < "$TMP/magenta.c" > "$TMP/magenta.c.tmp"
        mv "$TMP/magenta.c.tmp" "$TMP/magenta.c"
        python3 "$SCRIPT_DIR/variant_patches/patch_magenta.py" "$R" "$TMP/magenta.c"
        ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
        rm -rf "$TMP"
    fi

    # The patch helper is a ROOT-only artifact; strip it from the variant
    # so nothing weakening-related ships inside the task folder.
    rm -rf "$VARIANT_DIR/variant_patches"
done
