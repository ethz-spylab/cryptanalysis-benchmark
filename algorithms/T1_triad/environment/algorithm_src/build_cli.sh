#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract triad sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/triad.zip
unzip triad.zip

# Copy source files from the reference implementation (triadaev1 variant)
cp triad/Implementations/crypto_aead/triadaev1/ref/encrypt.c algorithm_encrypt.c
cp triad/Implementations/crypto_aead/triadaev1/ref/api.h .
cp triad/Implementations/crypto_aead/triadaev1/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
