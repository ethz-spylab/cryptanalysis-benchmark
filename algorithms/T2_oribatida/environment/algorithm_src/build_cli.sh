#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Oribatida sources
# wget https://csrc.nist.gov/CSRC/media/Projects/lightweight-cryptography/documents/round-2/submissions-rnd2/oribatida.zip
unzip -o oribatida.zip

# Copy source files from the reference implementation.
# We use the smaller/simpler parameter set Oribatida-192-96 (oribatida192v12):
# 128-bit key, 64-bit nonce, 96-bit tag, SimP-192 permutation.
# The reference encrypt.c includes the self-contained SimP_192.h header, so a
# single-file compile pulls in the whole implementation.
cp oribatida/Implementations/crypto_aead/oribatida192v12/ref/encrypt.c algorithm_encrypt.c
cp oribatida/Implementations/crypto_aead/oribatida192v12/ref/SimP_192.h .
cp oribatida/Implementations/crypto_aead/oribatida192v12/ref/api.h .
cp oribatida/Implementations/crypto_aead/oribatida192v12/ref/crypto_aead.h .

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
