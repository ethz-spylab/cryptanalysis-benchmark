#!/bin/bash
# CRYPTON scaling-down variants (Approach A: reduce ROUNDS).
#
# crypton1.c has no #define ROUNDS macro. Encrypt unrolls 11 alternating
# f0_rnd / f1_rnd calls, then gamma_tau, then post-whitening with
# e_key[48..51] (12 rounds total). Decrypt mirrors with d_key.
#
# Recipe (variant_workfolder/final_fixes_recommendation.md, CRYPTON entry):
# truncate the unrolled call list, repoint the post-whitening offset to
# e_key[4*R..4*R+3], and rebuild the d_key[0..3] override so decrypt's
# pre-whitening inverts the new post-W. Rather than re-deriving the d_key
# tail by hand, we KEEP the upstream key schedule (52 e_keys, 52 d_keys)
# and remap which entries the reduced encrypt/decrypt use:
#   - reduced encrypt uses e_key[0..3] (pre-W), e_key[4..(4(R-1)+3)]
#     (R-1 unrolled f-rnd calls), e_key[4R..4R+3] (post-W after row_perm).
#   - reduced decrypt uses d_key[0..3] (pre-W, OVERRIDDEN to equal the new
#     post-W key), d_key[4(13-R)..47] (the SAME inverse-round keys that
#     full-CRYPTON decrypt would use to invert encrypt rounds R-1..1, i.e.
#     the LAST R-1 calls of upstream decrypt's unrolled list), and
#     d_key[48..51] (post-W = upstream pre-W inverse, unchanged by our
#     patch).
#
# Parity. R-1 f-rnd calls starting with f0: state ends in b1 iff (R-1) is
# odd. CRYPTON v1.0's involution (decrypt(encrypt(x))=x) only round-trips
# cleanly when n_calls is odd: at even n_calls the F-chain ends in b0, and
# even with a b0->b1 copy before gamma_tau, the d-key chain we reuse from
# upstream (which encodes G o F_chain_e^{-1} o G, not just F_chain_e^{-1})
# does not undo the modified encrypt path. We therefore restrict the band
# choice to R values with odd (R-1): R=8, R=6, R=4 — all parity-clean.
#
# Variants. Hard R=8, Medium R=6, Easy R=4. The addendum's R=5 medium/easy
# is unreachable under this approach (see IMPLEMENTATION_NOTES.md). Per-
# round security gain ~2^20-2^25 per the spec; round-trip is enforced via
# test_variants.sh.
#
# Concealment design (generation-time repack): the weakening is applied by
# variant_patches/patch_crypton.py — a committed helper that lives at the
# algorithm ROOT (sibling of environment/), so it never enters the Docker
# build context. For each band we unzip the variant's archive into a temp
# dir, normalise CRLF (as build_cli.sh does), run the patch helper on the
# extracted crypton1.c, then repack into the SAME archive name. build_cli.sh
# is left byte-identical to base and no patch artifact lands under
# environment/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="CRYPTON.zip"
TARGET_FILE="crypton1.c"   # the upstream cipher source inside the archive (root level)
PATCHER="$SCRIPT_DIR/variant_patches/patch_crypton.py"

# band | R (total rounds incl. final gamma_tau-round)
A_VARIANTS=(
    "hard|8"
    "medium|6"
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

    # Normalise line endings exactly as build_cli.sh does before the patch's
    # regexes run on the cipher source.
    tr -d '\r' < "$TMP/$TARGET_FILE" > "$TMP/$TARGET_FILE.tmp"
    mv "$TMP/$TARGET_FILE.tmp" "$TMP/$TARGET_FILE"

    python3 "$PATCHER" "$TMP/$TARGET_FILE" "$R"

    # Repack into the SAME archive name with the same internal layout (files
    # at archive root), so build_cli.sh's unzip/cp paths are unchanged.
    rm -f "$ARCH"
    ( cd "$TMP" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # Drop the committed patch artifacts from the variant — they must never
    # ship inside a task's environment.
    rm -rf "$VARIANT_DIR/variant_patches"
done
