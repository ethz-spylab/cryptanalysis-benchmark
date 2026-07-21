#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract cilipadi sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/cilipadi.zip
unzip cilipadi.zip

# Copy source files from the reference implementation (cilipadi128v1mild variant)
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/encrypt.c algorithm_encrypt.c
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/cilipadi.c .
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/cilipadi.h .
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/led.c .
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/led.h .
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/api.h .
cp cilipadi/Implementations/crypto_aead/cilipadi128v1mild/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c cilipadi.c led.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
