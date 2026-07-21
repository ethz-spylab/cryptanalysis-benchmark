#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Qameleon sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/qameleon.zip
unzip -o qameleon.zip

# Copy source files from the reference implementation
# (qameleon12812864gpv1: 128-bit key, 128-bit tag, 64-bit nonce general-purpose variant)
VARIANT_DIR=qameleon/Implementations/crypto_aead/qameleon12812864gpv1/ref
cp "$VARIANT_DIR/encrypt.c" algorithm_encrypt.c
cp "$VARIANT_DIR/qarma128_14.h" .
cp "$VARIANT_DIR/api.h" .
cp "$VARIANT_DIR/crypto_aead.h" .

# Fix the vendored api.h's incorrect CRYPTO_ABYTES.
# The reference api.h declares CRYPTO_ABYTES=39, which is wrong: the actual
# ciphertext overhead of this variant is TAGLENGTH(16) + the 8-byte trailing
# message-length field = 24 bytes, and crypto_aead_decrypt itself requires
# clen % 16 == 8 (39 % 16 == 7 is not even a valid ciphertext length).
sed -i 's/#define[[:space:]]\+CRYPTO_ABYTES[[:space:]]\+39/#define CRYPTO_ABYTES 24/' api.h

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
