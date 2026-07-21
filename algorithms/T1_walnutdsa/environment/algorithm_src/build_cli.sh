#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract WalnutDSA sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/WalnutDSA.zip
unzip -o WalnutDSA.zip

# WalnutDSA ships a single shared reference tree; the parameter set and rewriting
# method are selected at compile time via #defines / -D flags (see api.h and the
# upstream Makefile). We build the walnut128 reference variant with the default
# BKL rewriting method (the api.h default).
REF="WalnutDSA/Reference_Implementation/walnut"
SUPPORT="WalnutDSA/Supporting_Documentation"

# Core reference sources/headers (key generation, signing, verification, utils).
cp "$REF"/*.c .
cp "$REF"/*.h .

# NIST-provided AES-CTR DRBG (randombytes / randombytes_init), pulled in by
# ae_lib.c via rng.h under the WORKING_COPY build, plus the crypto_sign.h that
# sign.c includes. We do NOT copy main.c / PQCgenKAT_sign.c (they have their own
# main); our cli.c provides main().
cp "$SUPPORT"/rng.c .
cp "$SUPPORT"/rng.h .
cp "$SUPPORT"/crypto_sign.h .

# Install necessary dependencies. rng.c (AES-CTR DRBG) and ae_lib.c's SHA-256/512
# (under WORKING_COPY) both use OpenSSL.
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
#   -D WALNUT -D WALNUT_SECURITY_LEVEL=128 : select the walnut128 parameter set
#       (BKL rewriting is api.h's default).
#   -D WORKING_COPY : use the local OpenSSL SHA-2 + NIST rng.h instead of the
#       SUPERCOP-only crypto_hash_* / randombytes.h headers (required to build
#       outside SUPERCOP, per the upstream README).
#   -fcommon : tolerate upstream tentative definitions; never edit the upstream
#       tree.
#   -lcrypto for the DRBG and SHA-2, -lm for math.
gcc -O2 -fcommon -o cli \
    -D WALNUT -D WALNUT_SECURITY_LEVEL=128 -D WORKING_COPY \
    cli.c sign.c ae_crypto.c ae_lib.c rng.c \
    -I. -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
