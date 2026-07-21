#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract NTS-KEM sources (NIST PQC Round 1 package)
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/NTS_KEM.zip
unzip -o NTS_KEM.zip

# Smallest parameter set: NTS-KEM(12, 64), reference implementation.
SRC_DIR="NTS-KEM/Reference_Implementation/kem/nts_kem_12_64"

# Copy all source and header files from the chosen variant into the build dir.
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .
# The NIST AES-CTR DRBG (random.c includes "aes_drbg.h" when NIST_DRBG_AES is set)
cp "$SRC_DIR"/nist/aes_drbg.c .
cp "$SRC_DIR"/nist/aes_drbg.h .

# Remove files that carry their own main() (KAT/test harnesses) — kept out of
# the compile so cli.c provides the only main.
rm -f PQCgenKAT_kem.c main.c ntskem_test.c ntskem_test.h

# Install necessary dependencies (OpenSSL for the AES-CTR DRBG in aes_drbg.c)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
#   -DNIST_DRBG_AES   selects the OpenSSL AES-CTR DRBG path in random.c,
#                     which exposes randombytes_init() (used by cli.c init_rng).
#   -DNTSKEM_M=12 -DNTSKEM_T=64  match the chosen parameter set (used by kem.c).
#   -fcommon          tolerate the upstream's tentative-definition globals.
#   -lcrypto          aes_drbg.c calls into OpenSSL libcrypto; -ldl for its deps.
gcc -O2 -std=c99 -fcommon -DNIST_DRBG_AES -DNTSKEM_M=12 -DNTSKEM_T=64 \
    -o cli \
    cli.c \
    additive_fft.c berlekamp_massey.c ff.c keccak.c kem.c \
    m4r.c matrix_ff2.c nts_kem.c polynomial.c random.c stack.c aes_drbg.c \
    -I. -lcrypto -ldl

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
