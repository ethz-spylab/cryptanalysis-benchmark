#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract the upstream BIKE v5.2 reference implementation.
# The bikesuite.org TLS certificate is expired, so disable cert checking.
ARCHIVE_URL="https://bikesuite.org/files/v5.2/Reference_Implementation.2024.10.10.1.zip"
ARCHIVE_NAME="Reference_Implementation.2024.10.10.1.zip"

# wget --no-check-certificate -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
unzip -o "$ARCHIVE_NAME"

# Install dependencies (BIKE uses NTL, GMP, gf2x, OpenSSL).
apt-get update
apt-get install -y libntl-dev libgmp-dev libgf2x-dev libssl-dev

# Stage the CLI driver inside the upstream source tree so includes resolve.
SRC_DIR="$SCRIPT_DIR/Reference_Implementation"
cp cli.c cli_stdin.h "$SRC_DIR/"

cd "$SRC_DIR"

# Compile. The upstream Makefile uses g++ on every .c plus ntl.cpp; mirror that.
# -DNIST_RAND=1 selects the AES-CTR DRBG seeded from /dev/urandom (via the
# cli's randombytes_init) instead of the insecure rand() fallback.
g++ -O3 -m64 -std=c++11 -fpermissive \
    -DNIST_RAND=1 -DVERBOSE=0 \
    -I. -IFromNIST \
    cli.c \
    conversions.c decode.c hash_wrapper.c kem.c ring_buffer.c \
    sampling.c shake_prng.c threshold.c utilities.c \
    ntl.cpp FromNIST/rng.c \
    -lntl -lgmp -lgf2x -lssl -lcrypto -lpthread -lm -ldl \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
