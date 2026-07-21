#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract simple sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/simple.zip
unzip simple.zip

# Copy source files from the reference implementation (simple64gift variant)
cp simple/Implementations/crypto_aead/simple64gift/ref/encrypt.c algorithm_encrypt.c
cp simple/Implementations/crypto_aead/simple64gift/ref/simple_64-128.c .
cp simple/Implementations/crypto_aead/simple64gift/ref/GIFT_64-128.c .
cp simple/Implementations/crypto_aead/simple64gift/ref/api.h .
cp simple/Implementations/crypto_aead/simple64gift/ref/crypto_aead.h .
cp simple/Implementations/crypto_aead/simple64gift/ref/blockcipher.h .
cp simple/Implementations/crypto_aead/simple64gift/ref/options.h .
cp simple/Implementations/crypto_aead/simple64gift/ref/simple.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c simple_64-128.c GIFT_64-128.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
