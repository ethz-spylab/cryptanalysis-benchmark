#!/bin/bash
# Approach A (reduce ROUNDS) per
#   algorithm_scaling_down/nist_aes/round_1/DFC.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (hard=6, medium=5*, easy=5).
#
# The reference (`dfc.c`) has eight unrolled `r_fun(blk, …, l_key + N)`
# calls per direction (key offsets 0,4,…,28). For R<8 we drop the
# trailing r_fun calls (those whose offset is >= 4*R). For odd R the
# f-chain leaves blk halves in the wrong orientation for the output
# half-swap; patch_dfc.py inserts a parity-correcting swap
# blk[0]<->blk[2], blk[1]<->blk[3] before the output writes in encrypt
# and right after the input reads in decrypt — the swap is its own
# inverse, so encrypt-then-decrypt composes to identity for any R in
# {1..8}.
#
# Concealment: the weakening helper (patch_dfc.py) lives in
# ./variant_patches/ at the algorithm ROOT — a sibling of environment/,
# so it never enters the Docker build context and is invisible to the
# agent. The weakened dfc.c is repacked into the SAME archive name
# (DFC-2.zip) so build_cli.sh stays byte-identical to base.
#
# Variant table:
#   - hard   R=6 — even, no parity swap.
#   - medium R=5 — odd, parity-fixed.
#   - easy   R=4 — even, no parity swap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="DFC-2.zip"

# Format: <band>|<R>
A_VARIANTS=(
    "hard|6"
    "medium|5"
    "easy|4"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    # patch_dfc.py's anchors expect LF endings; strip CR before patching.
    tr -d '\r' < "$TMP/dfc.c" > "$TMP/dfc.c.tmp" && mv "$TMP/dfc.c.tmp" "$TMP/dfc.c"
    python3 "$SCRIPT_DIR/variant_patches/patch_dfc.py" "$R" "$TMP/dfc.c"

    # Repack into the same archive name with the same top-level layout
    # (dfc.c, std_defs.h at the archive root) that build_cli.sh expects.
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
