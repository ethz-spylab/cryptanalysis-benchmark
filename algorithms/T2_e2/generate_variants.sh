#!/bin/bash
# Approach A (reduce ROUNDS) per
#   algorithm_scaling_down/nist_aes/round_1/E2.txt
# and MEDIUM_VARIANTS_ADDENDUM.md (hard=5, medium=4*, easy=4).
#
# The reference (`e2.c`) has twelve unrolled `f_fun(...)` calls per
# direction (key offsets 0,4,…,44), wrapped by bp_fun/ibp_fun. For R<12
# we drop the trailing f_fun calls (offset >= 4*R). For odd R the
# f-chain leaves (a,b,c,d) swapped relative to bp_fun's output;
# patch_e2.py inserts a parity-correcting (a,b)<->(c,d) swap before
# ibp_fun in encrypt and after bp_fun in decrypt — the swap is its own
# inverse, so encrypt-then-decrypt composes to identity for any R in
# {1..12}. (Earlier IMPLEMENTATION_NOTES entry flagged R=5 as not
# implementable via sed alone; the structural fix from
# variant_workfolder/final_fixes_recommendation.md unblocks it.)
#
# Variant table:
#   - hard   R=5 — odd, parity-fixed.
#   - medium R=4 — even, no parity swap (matches addendum's medium=4*).
#   - easy   R=2 — even, no parity swap (smallest sensible reduction
#                  that lands inside 2^30–2^40 per linear-cryptanalysis
#                  step ~16 bits per E2 round).
#
# Concealment: the weakening helper lives in ./variant_patches/
# (algorithm ROOT, a sibling of environment/ => never enters the Docker
# build context => invisible to the agent). The weakened e2.c is repacked
# into the same archive name (E2-2.zip) so build_cli.sh stays byte-
# identical to the base task and nothing weakening-related ships under
# environment/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="E2-2.zip"

# Format: <band>|<R>
A_VARIANTS=(
    "hard|5"
    "medium|4"
    "easy|2"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND R <<< "$entry"
    SUFFIX="${BAND}_r${R}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Generation-time patch + repack: unzip this variant's copy of the
    # archive, weaken upstream e2.c to R rounds, repack into the SAME
    # archive name. build_cli.sh is left untouched.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    # patch_e2.py's anchors expect LF endings, so strip CR first.
    tr -d '\r' < "$TMP/e2.c" > "$TMP/e2.c.tmp" && mv "$TMP/e2.c.tmp" "$TMP/e2.c"
    python3 "$SCRIPT_DIR/variant_patches/patch_e2.py" "$R" "$TMP/e2.c"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Drop the patch artifacts from the shipped variant.
    rm -rf "$VARIANT_DIR/variant_patches"
done
