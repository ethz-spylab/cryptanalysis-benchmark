#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Lepton sources
unzip -o Lepton.zip

# Copy all source and header files from the Reference_Implementation
cp Lepton/Reference_Implementation/*.c .
cp Lepton/Reference_Implementation/*.h .

# Remove harnesses that ship their own main() (we provide our own via cli.c)
rm -f PQCgenKAT_kem.c test.c

# Install necessary dependencies (OpenSSL for rng.c AES-256-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Build the SMALLEST parameter set (Light I)
# as the CCA KEM (api.h maps crypto_kem_* to lepton_kem_* unless LEPTON_CPA is set).
#
# Notes on the source set:
#   - precomp9-30-256.c is #include'd inside lepton_ow.c (a precomputed BCH table),
#     so it must NOT be compiled as a separate translation unit.
#   - lepton_kex.c is the CPA KEX implementation, unused by the CCA api.h wrappers.
#   - -fcommon: the NIST rng.c declares a tentative global (DRBG_ctx) reused across
#     translation units; modern GCC defaults to -fno-common.
gcc -O2 -fcommon -std=c99 -DLIGHT_I -o cli \
    cli.c rng.c fips202.c poly.c bch_codec.c lepton_ow.c lepton_kem.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
