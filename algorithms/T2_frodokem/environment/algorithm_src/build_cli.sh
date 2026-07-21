#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download upstream FrodoKEM round-3 submission.
ARCHIVE_URL="https://csrc.nist.gov/CSRC/media/Projects/post-quantum-cryptography/documents/round-3/submissions/FrodoKEM-Round3.zip"
ARCHIVE_NAME="FrodoKEM-Round3.zip"
# wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
unzip -o "$ARCHIVE_NAME"

apt-get update
apt-get install -y libssl-dev

# FrodoKEM-640 is the Category-1 parameter set; AES variant is the default.
SRC_DIR="$SCRIPT_DIR/FrodoKEM/FrodoKEM-20200930/Reference_Implementation/reference/FrodoKEM-640"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Flags selected from the upstream Makefile: reference implementation, x86-64,
# AES128 for matrix A generation, backed by OpenSSL for AES. We link in
# tests/rng.c (the NIST AES-CTR DRBG) rather than random/random.c so the cli's
# randombytes_init / randombytes semantics match the rest of the benchmark.
gcc -O3 -std=gnu11 \
    -D_AMD64_ -D_REFERENCE_ -D_AES128_FOR_A_ -D_USE_OPENSSL_ -DNIX \
    -I. -Itests \
    cli.c \
    frodo640.c util.c \
    aes/aes.c aes/aes_c.c \
    sha3/fips202.c \
    tests/rng.c \
    -lssl -lcrypto \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
