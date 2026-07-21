#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract KINDI sources
unzip -o KINDI.zip

# Chosen parameter set: KINDI-256-3-4-2 (smallest KEM set: n=256, L=3, lambda=128)
SRC="KINDI/Reference_Implementation/kem/KINDI-256-3-4-2"

# Copy all source and header files for the chosen parameter set
cp "$SRC"/*.c .
cp "$SRC"/*.h .

# Copy the FFT lookup-table tree referenced by relative includes in
# poly.h ("data_fft/256/...") and fft_transform.c ("data_fft/bitrev256.code").
cp -r "$SRC/data_fft" .

# Remove the KAT generation file (has its own main)
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
#   -lcrypto : rng.c AES256-CTR DRBG via OpenSSL
#   -lm      : params.h / poly.c use ceil()
#   -fcommon : tolerate the upstream's tentative global definitions
gcc -O2 -fcommon -o cli \
    cli.c core.c fft_transform.c fips202.c gen_randomness.c kem.c \
    poly.c poly_encode.c rng.c util.c \
    -I. -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
