#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract HYENA sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/hyena.zip
unzip -o hyena.zip

# Copy source files from the reference implementation (hyenav1 variant)
cp hyena/Implementations/crypto_aead/hyenav1/ref/encrypt.c algorithm_encrypt.c
cp hyena/Implementations/crypto_aead/hyenav1/ref/gift-128.c .
cp hyena/Implementations/crypto_aead/hyenav1/ref/hyena.h .
cp hyena/Implementations/crypto_aead/hyenav1/ref/api.h .
cp hyena/Implementations/crypto_aead/hyenav1/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c gift-128.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
