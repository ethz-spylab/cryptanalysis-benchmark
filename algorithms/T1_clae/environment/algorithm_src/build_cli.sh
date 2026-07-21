#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract clae sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/clae.zip
unzip clae.zip

# Copy source files from the reference implementation (clae128v1 variant)
cp clae/Implementations/crypto_aead/clae128v1/ref/encrypt.c algorithm_encrypt.c
cp clae/Implementations/crypto_aead/clae128v1/ref/api.h .
cp clae/Implementations/crypto_aead/clae128v1/ref/crypto_aead.h .

# Upstream api.h declares CRYPTO_ABYTES=16 but the implementation uses an
# 8-byte tag (CRYPTO_TAGBYTES in encrypt.c). The canonical cli.c sizes the
# decrypt output buffer as ct_len - CRYPTO_ABYTES; with the wrong value it
# under-allocates by 8 bytes and crypto_aead_decrypt corrupts the heap.
sed -i 's/^#define CRYPTO_ABYTES.*/#define CRYPTO_ABYTES 8/' api.h

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
