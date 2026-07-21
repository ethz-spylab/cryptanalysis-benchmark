#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract sundae-gift sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-2/submissions-rnd2/sundae-gift.zip
unzip sundae-gift.zip

# Copy source files from the reference implementation (sundaegift96v1 variant)
SRC=sundae-gift/Implementations/crypto_aead/sundaegift96v1/ref
cp $SRC/encrypt.c algorithm_encrypt.c
cp $SRC/sundae.c .
cp $SRC/sundae.h .
cp $SRC/gift128.c .
cp $SRC/gift128.h .
cp $SRC/api.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c sundae.c gift128.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
