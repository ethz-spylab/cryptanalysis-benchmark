#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract LOTUS sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/LOTUS.zip
unzip -o LOTUS.zip

# Copy all source and header files from the chosen KEM parameter set (LOTUS-128,
# the smallest set).
cp LOTUS/Reference_Implementation/kem/lotus128/*.c .
cp LOTUS/Reference_Implementation/kem/lotus128/*.h .

# Remove any KAT generation file with its own main (none under lotus128, but be safe).
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL: LOTUS uses EVP for SHA-512 + AES-128-CTR).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. randombytes() is defined inside cli.c (the upstream archive
# ships no rng.c). -fcommon avoids multiple-definition issues from the legacy
# ANSI sources; -lcrypto links OpenSSL EVP.
gcc -O2 -fcommon -o cli \
    cli.c cpa-pke.c crypto.c kem.c lwe-arithmetics.c pack.c sampler.c \
    -I. -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
