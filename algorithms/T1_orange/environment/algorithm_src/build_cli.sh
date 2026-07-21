#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract ORANGE sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/orange.zip
unzip -o orange.zip

# Copy source files from the reference implementation (ORANGE-Zest v1 variant)
cp orange/Implementations/crypto_aead/orangezestv1/ref/encrypt.c algorithm_encrypt.c
cp orange/Implementations/crypto_aead/orangezestv1/ref/orangemodule.h .
cp orange/Implementations/crypto_aead/orangezestv1/ref/photon.h .
cp orange/Implementations/crypto_aead/orangezestv1/ref/api.h .
cp orange/Implementations/crypto_aead/orangezestv1/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
