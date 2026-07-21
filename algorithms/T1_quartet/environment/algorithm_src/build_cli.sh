#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Quartet sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/quartet.zip
unzip -o quartet.zip

# Copy source files from the reference implementation (Quartet128v1 variant)
cp quartet/Implementations/crypto_aead/Quartet128v1/ref/encrypt.c algorithm_encrypt.c
cp quartet/Implementations/crypto_aead/Quartet128v1/ref/api.h .
cp quartet/Implementations/crypto_aead/Quartet128v1/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
