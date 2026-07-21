#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SIV-Rijndael256-AEAD sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/siv-rijndael256.zip
unzip -o siv-rijndael256.zip

# Copy source files from the reference AEAD implementation
# (sivrijndael256aead128v1 variant: 128-bit key, 128-bit nonce, 32-byte tag)
REF=siv-rijndael256/Implementations/crypto_aead/sivrijndael256aead128v1/ref
cp "$REF/encrypt.c" algorithm_encrypt.c
cp "$REF/rijndael256.c" .
cp "$REF/rijndael-alg-ref.c" .
cp "$REF/rijndael-alg-ref.h" .
cp "$REF/rijndael256.h" .
cp "$REF/siv.h" .
cp "$REF/api.h" .
cp "$REF/boxes-ref.dat" .   # #include'd at compile time by rijndael-alg-ref.c

# Compile the CLI. rijndael256.c pulls in <math.h>, so link libm.
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c rijndael256.c rijndael-alg-ref.c \
    -I. -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
