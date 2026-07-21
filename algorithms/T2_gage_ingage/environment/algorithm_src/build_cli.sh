#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract gage-ingage sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/gage-ingage.zip
unzip gage-ingage.zip

# Copy source files from the reference implementation
# (ingage1k128n096c224r008: 128-bit key, 96-bit nonce, 224-bit capacity, 8-bit rate)
SRC=gage-ingage/Implementations/crypto_aead/ingage1k128n096c224r008/ref
cp $SRC/encrypt.c algorithm_encrypt.c
cp $SRC/constants.c .
cp $SRC/constants.h .
cp $SRC/parameters.h .
cp $SRC/api.h .
cp $SRC/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c constants.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
