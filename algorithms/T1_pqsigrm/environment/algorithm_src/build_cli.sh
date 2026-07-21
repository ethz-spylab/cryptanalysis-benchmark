#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract pqsigRM sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/pqsigRM.zip
unzip -o pqsigRM.zip

# Use the smallest parameter set, pqsigRM-4-12 (Category 1, 128-bit security).
REF="pqsigRM/Reference_Implementation/pqsigrm412"

# Copy all reference-implementation sources and headers for pqsigRM-4-12.
# This includes keypair.c (crypto_sign_keypair), sign.c (crypto_sign),
# open.c (crypto_sign_open), common.c, matrix.c, nearest_vector.c and rng.c
# (the NIST AES-CTR DRBG, backed by OpenSSL).
cp "$REF"/*.c .
cp "$REF"/*.h .

# pqsigRM reads two publicly-known, key-independent data files from the current
# working directory at runtime: parity_check.pqsigrm (used by keypair.c) and
# lead_diff.pqsigrm (used by sign.c). Copy them next to the cli binary so they
# are present when the game controller runs ./cli from /crypto_oracle.
cp "$REF"/parity_check.pqsigrm .
cp "$REF"/lead_diff.pqsigrm .

# pqsigRM has no separate KAT main inside the parameter dir, but guard against
# any stray main-bearing harness just in case.
rm -f PQCgenKAT_sign.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG and common.c
# SHA-512).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. -fcommon avoids multiple-definition issues from upstream
# tentative definitions; never edit the upstream tree. nearest_vector.c uses
# math functions, so link -lm. rng.c uses OpenSSL, so link -lssl -lcrypto.
gcc -O2 -fcommon -o cli \
    cli.c common.c keypair.c matrix.c nearest_vector.c open.c rng.c sign.c \
    -I. -lssl -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
