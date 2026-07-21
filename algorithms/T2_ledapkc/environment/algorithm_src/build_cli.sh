#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract LEDApkc sources (Round-1 NIST PQC submission).
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/LEDApkc.zip
unzip -o LEDApkc.zip

# The reference implementation lives under Reference_Implementation/LEDApkc with
# sources in library/ and headers in include/. Copy all .c/.h next to cli.c.
cp Reference_Implementation/LEDApkc/library/*.c .
cp Reference_Implementation/LEDApkc/include/*.h .

# No KAT-generation main() ships in the reference library (it is a static
# library), so there is no PQCgenKAT_encrypt.c to remove. Guard anyway in case
# the archive layout changes.
rm -f PQCgenKAT_encrypt.c

# LEDApkc ships its own self-contained AES-256 (aes256.c) and SHA-3 (sha3.c)
# plus a NIST-style AES-CTR DRBG (rng.c). No OpenSSL / GMP needed.
#
# Parameter selection (smallest / lowest security category, T2 variant):
#   CATEGORY=1  -> NIST category 1
#   N0=2        -> 2 circulant blocks (P=27779, t=224 errors)
# CPU_WORD_BITS=64 picks the 64-bit DIGIT limb type required by gf2x_limbs.h.
# -fcommon tolerates the upstream tentative-definition style; -std=c99 matches
# the upstream Makefile; -lm covers the math the gf2x code links against.
gcc -O3 -std=c99 -fcommon \
    -DCATEGORY=1 -DN0=2 -DCPU_WORD_BITS=64 \
    -I. \
    -o cli \
    cli.c \
    aes256.c bf_decoding.c constant_weight_codec.c encrypt.c \
    gf2x_arith.c gf2x_arith_mod_xPplusOne.c H_Q_matrices_generation.c \
    mceliece_cca2_decrypt.c mceliece_cca2_encrypt.c mceliece_keygen.c \
    rng.c sha3.c \
    -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
