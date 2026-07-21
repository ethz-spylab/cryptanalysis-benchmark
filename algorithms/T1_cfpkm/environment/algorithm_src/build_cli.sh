#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract CFPKM sources (NIST PQC Round 1 submission)
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/CFPKM.zip
unzip -o CFPKM.zip

REF="CFPKM/Reference_Implementation/kem/CFPKM128"

# Copy all reference source + header modules into the build dir.
cp "$REF"/src/*.c .
cp "$REF"/include/*.h .

# Remove the KAT generation harness (has its own main()).
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. CFPKM exposes the standard NIST crypto_kem_* API via api.h,
# so the canonical KEM cli.c is a drop-in. rng.c needs OpenSSL (-lcrypto);
# the headers include <math.h> so -lm is linked defensively.
gcc -O2 -fcommon -o cli \
    cli.c kem.c rng.c \
    -I. -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
