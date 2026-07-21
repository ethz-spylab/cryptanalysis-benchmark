#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract flexaead sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/flexaead.zip
unzip flexaead.zip

# Copy source files from the reference implementation (flexaead128b064v1 variant)
cp flexaead/Implementations/crypto_aead/flexaead128b064v1/ref/encrypt.c algorithm_encrypt.c
cp flexaead/Implementations/crypto_aead/flexaead128b064v1/ref/encrypt.h .
cp flexaead/Implementations/crypto_aead/flexaead128b064v1/ref/api.h .

# Upstream api.h declares CRYPTO_ABYTES=16 but the implementation uses an
# 8-byte tag (TAGSIZE = BLOCKSIZE in encrypt.h). The canonical cli.c sizes
# the decrypt output buffer as ct_len - CRYPTO_ABYTES; with the wrong value
# it under-allocates by 8 bytes and crypto_aead_decrypt corrupts the heap.
sed -i 's/^#define CRYPTO_ABYTES.*/#define CRYPTO_ABYTES 8/' api.h

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
