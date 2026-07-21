#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract the Mersenne-756839 sources
unzip -o Mersenne_756839.zip

# Copy the Reference_Implementation sources (the single SECURITYLVL=256
# parameter set, "Mersenne756839").
cp Mersenne_756839/Reference_Implementation/*.c .
cp Mersenne_756839/Reference_Implementation/*.h .

# Reference_Implementation ships only Mersenne_kem.c + api.h; the NIST DRBG
# (rng.c/rng.h) lives in the KAT folder. Pull it in so init_rng() works.
cp Mersenne_756839/KAT/rng.c .
cp Mersenne_756839/KAT/rng.h .

# Remove the KAT generation file (has its own main) if present
rm -f PQCgenKAT_kem.c

# Install build dependencies:
#   - libgmp-dev: big-integer arithmetic over the Mersenne prime (mpz_*)
#   - libssl-dev: AES-256-CTR DRBG + SHA in rng.c / Mersenne_kem.c
apt-get update
apt-get install -y libgmp-dev libssl-dev

# Compile the CLI. -fcommon avoids multiple-definition errors from the
# upstream's global DRBG_ctx. -lgmp for GMP, -lcrypto for OpenSSL rng.
gcc -O2 -fcommon -o cli \
    cli.c Mersenne_kem.c rng.c \
    -I. -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
