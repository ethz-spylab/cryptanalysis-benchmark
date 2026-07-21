#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract NTRU-HRSS-KEM sources (NIST Round-1 standalone submission).
unzip NTRU_HRSS_KEM.zip

# Parameter set: ntruhrss701 (the only/primary set in Reference_Implementation).
REF="NIST-PQ-Submission-NTRU-HRSS-KEM-20171130/Reference_Implementation/crypto_kem/ntruhrss701"

# Copy all reference source and header files.
cp "$REF"/*.c .
cp "$REF"/*.h .

# Remove the KAT generation file (has its own main).
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
gcc -O2 -fcommon -o cli \
    cli.c cbd.c fips202.c ntrukem.c owcpa.c poly.c verify.c rng.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
