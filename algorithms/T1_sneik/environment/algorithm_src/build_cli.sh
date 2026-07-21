#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract sneik sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/sneik.zip
unzip sneik.zip

# Copy source files from the reference implementation (sneiken128 variant)
cp sneik/Implementations/crypto_aead/sneiken128/ref/encrypt.c algorithm_encrypt.c
cp sneik/Implementations/crypto_aead/sneiken128/ref/blnk.c .
cp sneik/Implementations/crypto_aead/sneiken128/ref/blnk.h .
cp sneik/Implementations/crypto_aead/sneiken128/ref/sneik_f512_c99.c .
cp sneik/Implementations/crypto_aead/sneiken128/ref/sneik_param.h .
cp sneik/Implementations/crypto_aead/sneiken128/ref/api.h .
cp sneik/Implementations/crypto_aead/sneiken128/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c blnk.c sneik_f512_c99.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
