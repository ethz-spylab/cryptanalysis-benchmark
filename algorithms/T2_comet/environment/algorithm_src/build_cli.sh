#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract COMET sources
# wget https://csrc.nist.gov/CSRC/media/Projects/lightweight-cryptography/documents/round-2/submissions-rnd2/comet.zip
unzip -o comet.zip

# Copy source files from the reference implementation.
# Variant: COMET-64 with Speck (comet64speckv1) -- the smallest parameter set
# (64-bit block, 128-bit key, 15-byte nonce, 8-byte tag).
REF=comet/Implementations/crypto_aead/comet64speckv1/ref
cp "$REF/encrypt.c" algorithm_encrypt.c
cp "$REF/comet_64-128_and_128-128.c" comet_core.c
cp "$REF/speck_64-128_and_128-128.c" speck.c
cp "$REF/comet.h" .
cp "$REF/blockcipher.h" .
cp "$REF/options.h" .
cp "$REF/api.h" .
cp "$REF/crypto_aead.h" .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c comet_core.c speck.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
