#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract sycon sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/sycon.zip
unzip sycon.zip

# Copy source files from the reference implementation (syconaer64128v1 variant)
cp sycon/Implementations/crypto_aead/syconaer64128v1/ref/encrypt.c algorithm_encrypt.c
cp sycon/Implementations/crypto_aead/syconaer64128v1/ref/sycon.c .
cp sycon/Implementations/crypto_aead/syconaer64128v1/ref/sycon.h .
cp sycon/Implementations/crypto_aead/syconaer64128v1/ref/api.h .
cp sycon/Implementations/crypto_aead/syconaer64128v1/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c sycon.c \
    -I. -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
