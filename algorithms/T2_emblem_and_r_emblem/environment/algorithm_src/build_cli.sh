#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract the EMBLEM / R.EMBLEM submission archive
unzip -o EMBLEM_R_EMBLEM.zip

# We implement the EMBLEM KEM (the primary scheme in the bundle).
# Its standard NIST crypto_kem_* API lives in the KAT harness folder
# KAT/EMBLEM (kem.c + rng.c + api.h + rng.h); the stand-alone
# Reference_Implementation/EMBLEM_REF tree is only a self-contained timing
# demo with a non-standard, struct-based API and no rng.c.
SRC="EMBLEM_R_EMBLEM/KAT/EMBLEM"
cp "$SRC"/kem.c .
cp "$SRC"/rng.c .
cp "$SRC"/api.h .
cp "$SRC"/rng.h .

# Remove the KAT generation file (it has its own main)
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG and SHA-256)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
#   -mavx2   : kem.c includes <immintrin.h>
#   -fcommon : tolerate the upstream's tentative/global definitions
#   -I.      : pick up api.h / rng.h next to the sources
#   -lcrypto : rng.c (AES-256-CTR DRBG) and kem.c (SHA-256)
gcc -O2 -mavx2 -fcommon -o cli \
    cli.c kem.c rng.c \
    -I. -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
