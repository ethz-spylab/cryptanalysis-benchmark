#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract LEDAkem sources (Round-1 NIST PQC submission).
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/LEDAkem.zip
unzip -o LEDAkem.zip

# The reference implementation lives under Reference_Implementation/KEM with
# sources in library/ and headers in include/. Copy all .c/.h next to cli.c.
cp Reference_Implementation/KEM/library/*.c .
cp Reference_Implementation/KEM/include/*.h .

# No KAT-generation main() ships in the reference library (it is a static
# library), so there is no PQCgenKAT_kem.c to remove. Guard anyway in case the
# archive layout changes.
rm -f PQCgenKAT_kem.c

# LEDAkem ships its own self-contained AES-256 (aes256.c) and SHA-3 (sha3.c)
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
    aes256.c bf_decoding.c gf2x_arith.c gf2x_arith_mod_xPplusOne.c \
    H_Q_matrices_generation.c kem.c niederreiter_decrypt.c \
    niederreiter_encrypt.c niederreiter_keygen.c rng.c sha3.c \
    -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
