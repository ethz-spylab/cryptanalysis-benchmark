#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract BIG_QUAKE sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/BIG_QUAKE.zip
unzip BIG_QUAKE.zip

# Copy all source and header files from Reference_Implementation/BIG_QUAKE_1
cp BIG_QUAKE/Reference_Implementation/BIG_QUAKE_1/*.c .
cp BIG_QUAKE/Reference_Implementation/BIG_QUAKE_1/*.h .

# Remove the KAT generation file (has its own main)
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI
gcc -O2 -fcommon -o cli \
    cli.c decode.c gf.c goppa.c keccak.c kem.c m2e.c permutation.c poly.c rng.c roots.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
