#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract limdolen sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/limdolen.zip
unzip limdolen.zip

# Copy source files from the reference implementation (limdolen128v1 variant)
cp limdolen/Implementations/crypto_aead/limdolen128v1/ref/encrypt.c algorithm_encrypt.c
cp limdolen/Implementations/crypto_aead/limdolen128v1/ref/api.h .
cp limdolen/Implementations/crypto_aead/limdolen128v1/ref/crypto_aead.h .
cp limdolen/Implementations/crypto_aead/limdolen128v1/ref/crypto_hash.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
