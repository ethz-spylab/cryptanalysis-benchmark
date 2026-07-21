#!/bin/bash
# FSB scaling-down variants (Approach A: structural parameter reduction).
#
# Per `variant_workfolder/final_fixes_recommendation.md` § FSB we pick three
# power-of-2-clean (n, w, r, p) tuples and override the 256-bit row of
# `parameters[]` in `fsb.c`. The Pi table shipped upstream is large enough
# (2 MiB of pseudo-random bytes) to be sliced for the smaller tuples — Pi
# is only used as a deterministic byte source for the QC matrix
# construction, so any deterministic source still leaves FSB a hash. An
# attacker computing the reduced FSB sees the same Pi bytes we do, which
# is the relevant property.
#
#   Hard   (2^60–2^80):  n=2^17, w=64,  r=128, p=131  (ISD ≈ 2^70)
#   Medium (2^40–2^60):  n=2^14, w=32,  r=64,  p=67   (ISD ≈ 2^50)
#   Easy   (2^30–2^40):  n=2^12, w=16,  r=32,  p=37   (ISD ≈ 2^35)
#
# Power-of-2 invariants the implementation requires:
#   - r | n  (state->b = n / r)
#   - n / w  is a power of 2  (state->bpc = logarithm(n/w))
#   - w | r  (state->bfiv = r / w)
#   - w | (w*bpc - r)  (state->bfm = inputsize / w)
# All three tuples satisfy these.
#
# Concealment: the weakening is expressed as committed unified-diff patches in
# ./variant_patches/ (at the algorithm ROOT, a sibling of environment/, so they
# never enter the Docker build context => invisible to the agent). For each
# band we unzip the variant's own copy of FSB.zip, apply the band patch to the
# extracted fsb.c, repack into the SAME archive name, and drop variant_patches/.
# build_cli.sh is left byte-identical to base.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="FSB.zip"
EXTRACT_ROOT="FSB"   # top-level dir inside FSB.zip

# <band>|<n_shift>|<w_shift>|<r_shift>|<p>|<patch-file>
A_VARIANTS=(
    "easy|12|4|5|37|variant_easy.patch"
    "medium|14|5|6|67|variant_medium.patch"
    "hard|17|6|7|131|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NSH WSH RSH P PATCH <<< "$entry"
    SUFFIX="${BAND}_n2p${NSH}_w2p${WSH}_r2p${RSH}_p${P}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    # patch paths are a/FSB/...; -p1 strips the a/ prefix, resolved against $TMP
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" "$EXTRACT_ROOT" )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
