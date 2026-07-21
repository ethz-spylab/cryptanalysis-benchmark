#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Rainbow sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Rainbow.zip
unzip -o Rainbow.zip

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG and SHA hashing)
apt-get update
apt-get install -y libssl-dev

# Copy all source and header files from the classic GF(16) level-I parameter set
# (Reference_Implementation/Ia == Rainbow(GF(16),32,32,32)). The default param set
# in rainbow_config.h is already _RAINBOW16_32_32_32, so no -D override is needed.
cp Rainbow/Reference_Implementation/Ia/*.c .
cp Rainbow/Reference_Implementation/Ia/*.h .

# Remove any KAT generation / main files (the reference Ia tree ships none, but be safe)
rm -f PQCgenKAT_sign.c

# Compile the CLI.
#   cli.c       - the benchmark CLI wrapper (msg||sig layout, matches sign.c)
#   sign.c      - NIST crypto_sign_* wrapper around the core routines
#   rainbow_16.c- core Rainbow over GF(16)
#   hash_utils.c- OpenSSL SHA-2 adaptor
#   prng_utils.c- PRNG routing (defaults to the NIST DRBG in rng.c)
#   rng.c       - NIST AES-256-CTR DRBG (seeded from /dev/urandom by cli.c)
# -fcommon is needed because the legacy upstream relies on common symbols.
# prng_utils.c references the OpenSSL 1.0 API FIPS_mode_set(), which was removed
# in OpenSSL 3.0 and would otherwise break linking. That symbol lives only in
# openssl_prng_bytes(), a code path that is never taken at runtime (prng routing
# defaults to the NIST DRBG in rng.c, which cli.c seeds from /dev/urandom). We
# neutralize it with a compile-time macro instead of editing the upstream source.
gcc -O2 -fcommon -D'FIPS_mode_set(x)=0' -o cli \
    cli.c sign.c rainbow_16.c hash_utils.c prng_utils.c rng.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
