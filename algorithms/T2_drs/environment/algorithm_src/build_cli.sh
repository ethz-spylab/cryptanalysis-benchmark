#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract DRS sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/DRS.zip
unzip -o DRS.zip

# Copy all source and header files from the Reference_Implementation
cp DRS/Reference_Implementation/*.c .
cp DRS/Reference_Implementation/*.h .

# Select the smallest official NIST parameter set (security level 128) as api.h.
# (The API_H folder ships api.h.{128,192,256}; the in-tree KAT api.h is a toy
#  set used only to keep KAT files small.)
cp DRS/Reference_Implementation/API_H/api.h.128 api.h

# Remove the KAT generation file (has its own main)
rm -f PQCgenKAT_sign.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
# - sign.c pulls in the rest of the algorithm via headers
#   (SHAKE512.h -> Keccak-readable-and-compact.c, setup.h, verify.h, ...).
# - setup.h uses <math.h> -> link -lm.
# - rng.c uses OpenSSL -> link -lssl -lcrypto.
# - -fcommon avoids multiple-definition errors from the upstream headers that
#   define globals without `extern`.
gcc -O2 -fcommon -o cli \
    cli.c sign.c rng.c \
    -I. -lssl -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
