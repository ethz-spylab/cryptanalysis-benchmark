#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Compact-LWE sources
unzip -o Compact_LWE.zip

# Copy all source and header files from the Reference_Implementation.
cp "Compact-LWE-Public-Key-Enc/Reference_Implementation/"*.c .
cp "Compact-LWE-Public-Key-Enc/Reference_Implementation/"*.h .

# Remove the KAT generation / performance test files (each has its own main()).
rm -f PQCgenKAT_encrypt.c Performance-test.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
#   - rng.c        : NIST AES-CTR DRBG (needs OpenSSL)
#   - compact-lwe.c: core scheme (needs -lm for math.h)
#   - mini-gmp.c   : bundled big-integer arithmetic (no system GMP needed)
#   - encrypt.c    : crypto_encrypt* API
#   - cli.c        : our CLI front-end
gcc -O2 -fcommon -std=c99 -o cli \
    cli.c encrypt.c compact-lwe.c mini-gmp.c rng.c \
    -I. -lssl -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
