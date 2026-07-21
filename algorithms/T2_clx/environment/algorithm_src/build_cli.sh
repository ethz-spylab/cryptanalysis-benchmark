#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract clx sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/clx.zip
unzip clx.zip

# Copy source files from the reference implementation (clx128 variant)
cp clx/Implementations/crypto_aead/clx128/ref/encrypt.c algorithm_encrypt.c
cp clx/Implementations/crypto_aead/clx128/ref/api.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
