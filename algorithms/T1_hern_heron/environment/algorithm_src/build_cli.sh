#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract hern-heron sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/hern-heron.zip
unzip hern-heron.zip

# Copy source files from the reference implementation (hern128v1 variant)
cp hern-heron/Implementations/crypto_aead/hern128v1/ref/encrypt.c algorithm_encrypt.c
cp hern-heron/Implementations/crypto_aead/hern128v1/ref/api.h .

# Create minimal crypto_aead.h (not included in the reference implementation)
cat > crypto_aead.h << 'HEADER'
#ifndef CRYPTO_AEAD_H
#define CRYPTO_AEAD_H

int crypto_aead_encrypt(
    unsigned char *c, unsigned long long *clen,
    const unsigned char *m, unsigned long long mlen,
    const unsigned char *ad, unsigned long long adlen,
    const unsigned char *nsec,
    const unsigned char *npub,
    const unsigned char *k);

int crypto_aead_decrypt(
    unsigned char *m, unsigned long long *mlen,
    unsigned char *nsec,
    const unsigned char *c, unsigned long long clen,
    const unsigned char *ad, unsigned long long adlen,
    const unsigned char *npub,
    const unsigned char *k);

#endif
HEADER

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
