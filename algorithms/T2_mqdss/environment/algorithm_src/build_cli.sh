#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract MQDSS sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-2/submissions/MQDSS-Round2.zip
unzip MQDSS-Round2.zip

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

REF_DIR="NIST-PQ-Submission-MQDSS-20190315/Reference_Implementation/crypto_sign/mqdss-48"

# Copy source and header files next to cli.c
cp "$REF_DIR"/*.c .
cp "$REF_DIR"/*.h .

# Drop the KAT generator which ships its own main()
rm -f PQCgenKAT_sign.c

# Compile the CLI
gcc -O3 -o cli \
    cli.c fips202.c gf31.c mq.c rng.c sign.c \
    -I. -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
