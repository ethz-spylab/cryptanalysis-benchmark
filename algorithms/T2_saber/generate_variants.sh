#!/bin/bash
# Approach C (shrink shared-key entropy) — fallback because Approach A
# (reduce SABER_L) and Approach B (reduce SABER_LOGP) require structural
# code changes (new SABER_L=1 case / rewriting the 10-bit BS2POLp /
# POLp2BS packers) that are well beyond a sed-level patch.
#
# We zero the high bytes of the shared key written by `sha3_256(k, kr, 64)`
# at the end of both crypto_kem_enc and crypto_kem_dec in kem.c. Both sides
# perform the same truncation, so the round-trip stays consistent.
#
# Bands (CRYPTO_BYTES = 16 for the LightSaber l=2 build):
#   Hard (2^60-2^80, ~80-bit):   keep first 10 bytes
#   Medium (2^40-2^60, ~56-bit): keep first  7 bytes  (interpolated; spec/
#                                addendum do not list a medium for C)
#   Easy (2^30-2^40, ~40-bit):   keep first  5 bytes
#
# Concealment design: the weakening lives in committed patch artifacts under
# ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never in
# the Docker build context => invisible to the agent). At generation time we
# unzip the variant's vendored archive, apply the band patch to the extracted
# source, and repack into the SAME archive name so build_cli.sh stays pristine
# (byte-identical to base).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="vendored-SABER.tar.gz"
EXTRACT_ROOT="SABER"   # top-level dir inside the archive; patch -d resolves against it

# band|keep-bytes|patch-file
A_VARIANTS=(
    "easy|5|variant_easy.patch"
    "medium|7|variant_medium.patch"
    "hard|10|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND KEEP PATCH <<< "$entry"
    SUFFIX="c_${BAND}_keep${KEEP}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    tar xzf "$ARCH" -C "$TMP"
    patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && tar czf "$ARCH" "$EXTRACT_ROOT" )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"

    # Approach-C entropy truncation zeroes the high bytes of the shared key, so
    # the real KEM output is visibly non-uniform. That lets the IND-CCA2
    # distinguishing game (KEMChosenCiphertextAttack2Game) be won for free — with
    # no cryptanalysis and independent of the retained-entropy band — which
    # completely bypasses the 2^40/2^56/2^80 brute-force cost the variant is meant
    # to gate. Drop that game for these variants and keep only the recovery games,
    # whose difficulty the bands actually measure. (The base T2_saber task keeps
    # KEMChosenCiphertextAttack2Game via its own possible_security_games.yml, since
    # full LightSaber is FO/IND-CCA2-secure and that game is a legitimate hard
    # target there.)
    cat > "$VARIANT_DIR/environment/possible_security_games.yml" <<'YML'
security_games:
  - KEMPrivateKeyRecoveryGame
  - KEMSharedSecretRecoveryGame
YML
done
