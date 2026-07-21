#!/bin/bash
# Approach A (reduce PARAMS_N). Three security bands per the round-3 spec
# + addendum:
#   - Hard   (2^60-2^80): PARAMS_N = 280
#   - Medium (2^40-2^60): PARAMS_N = 200
#   - Easy   (2^30-2^40): PARAMS_N = 152  (spec says 150; rounded up to the
#                                          nearest multiple of 8 — see below)
#
# σ (CDF_TABLE) and PARAMS_LOGQ are kept fixed.
#
# Each variant patches, in the extracted FrodoKEM-640 source:
#   1. PARAMS_N in frodo640.c.
#   2. CRYPTO_PUBLICKEYBYTES / CRYPTO_CIPHERTEXTBYTES / CRYPTO_SECRETKEYBYTES
#      in FrodoKEM-640/api.h (the cli sizes its buffers from these constants).
#      Formulae: PUB = 16 + 15*N ;  CT = 15*N + 120 ;  SK = 48 + 31*N.
#
# Why N must be a multiple of 8: frodo_macrify_reference.c walks the matrix
# A in stripes of PARAMS_STRIPE_STEP = 8. Off-multiple values leave a tail
# of uninitialised int16_t entries that AES then encrypts as part of an
# incomplete final block, which OpenSSL's EVP_EncryptUpdate refuses
# without explicit padding. 280, 200, and 152 all satisfy N % 8 == 0.
#
# Concealment: the weakening lives in ./variant_patches/ (algorithm ROOT,
# outside environment/ => never in the Docker build context => invisible to
# the agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays byte-identical to the base task.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="FrodoKEM-Round3.zip"

# band|N|patch-file  (N records the real parameter value in the folder name)
A_VARIANTS=(
    "easy|152|variant_easy.patch"
    "medium|200|variant_medium.patch"
    "hard|280|variant_hard.patch"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND N PATCH <<< "$entry"
    SUFFIX="${BAND}_n${N}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
