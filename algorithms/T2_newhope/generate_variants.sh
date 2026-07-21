#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="vendored-newhope.tar.gz"
EXTRACT_ROOT="newhope/ref"   # the dir patch_newhope.py edits inside the archive

# Approach A — NEWHOPE_N is gated by precomputed NTT/bit-reversal tables that
# only exist for N=512 / N=1024 (see IMPLEMENTATION_NOTES.md). Per
# `variant_workfolder/final_fixes_recommendation.md` (Section 3, "NewHope"),
# the recovered structural knob is the **CBD noise parameter k** (η). NewHope
# samples each LWE coefficient as hw(a) - hw(b) with a, b uniformly random
# 8-bit bytes (k=8). Reducing k narrows the noise distribution, which
# directly weakens LWE: dual-attack BKZ block size scales with η², so smaller
# η → smaller attack cost.
#
# We hold N = 512 (upstream) and reduce k:
#   Hard:   k = 6  (LWE cost ~2^75)
#   Medium: k = 4  (LWE cost ~2^50)
#   Easy:   k = 2  (LWE cost ~2^32)
#
# Concealment design (generation-time repack). The weakening lives in the
# committed patch artifact ./variant_patches/patch_newhope.py, which sits at the
# algorithm ROOT — a sibling of environment/ — so it never enters the Docker
# build context and is invisible to the agent. For each band we extract the
# variant's own copy of the archive to a temp dir, apply the patch there, and
# repack into the SAME archive name. build_cli.sh is left byte-identical to base
# (no injection), and patch_newhope.py applies:
#   1. params.h's `#define NEWHOPE_K 8` → the band's k.
#   2. poly.c's `#if NEWHOPE_K != 8 / #error / #endif` guard is deleted (the
#      hand-unrolled cbd works for any k ≤ 8 once we mask the input bytes).
#   3. poly.c's cbd reads `a = buf[2*j];` / `b = buf[2*j+1];` are masked to
#      the low k bits (`& ((1<<NEWHOPE_K)-1)`) so hw(a), hw(b) ∈ [0, k] —
#      the centered-binomial parameter is genuinely k, not 8.
# Stream-buffer size is left at upstream (128 bytes / 64 coeffs); the masked
# bits are simply discarded. NTT/bit-reversal tables are unaffected because
# they depend only on N. Upstream sources are CRLF; the patcher strips CR
# before its line-anchored edits.

# Format: <band>|<ETA>
A_VARIANTS=(
    "easy|2"
    "medium|4"
    "hard|6"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND ETA <<< "$entry"
    SUFFIX="${BAND}_eta${ETA}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    tar xzf "$ARCH" -C "$TMP"
    python3 "$SCRIPT_DIR/variant_patches/patch_newhope.py" "$TMP/$EXTRACT_ROOT" "$ETA"
    ( cd "$TMP" && rm -f "$ARCH" && tar czf "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
