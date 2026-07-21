#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Gui sources (the archive is vendored alongside this script; use
# download_source.sh to refresh it from upstream).
unzip -o Gui.zip

# Install necessary dependencies (OpenSSL for the NIST AES-CTR DRBG in rng.c
# and the SHA-2 hashing in hash_utils.c).
apt-get update
apt-get install -y libssl-dev

# Smallest parameter set (NIST security level I): Gui-184.
PARAM_DIR="Reference_Implementation/Gui-184"

# Copy all source and header files for the chosen parameter set into the build
# directory. This pulls in the standard NIST API (sign.c with
# crypto_sign_keypair / crypto_sign / crypto_sign_open) plus the Gui internals
# and the openssl-backed rng.c / hash_utils.c.
cp "$PARAM_DIR"/*.c .
cp "$PARAM_DIR"/*.h .

# Drop any KAT generation / standalone-main source files (none live inside the
# parameter directory, but guard against future archive layouts).
rm -f PQCgenKAT_sign.c PQCgenKAT_kem.c

# Compile the CLI. -fcommon avoids multiple-definition errors from the upstream
# globals; -I. picks up the in-tree headers.
#
# prng_utils.c references OpenSSL's FIPS_mode_set(), which was removed in
# OpenSSL 3.0 (the version shipped by the build image). That code path
# (openssl_prng_bytes) is only ever taken when the upstream "user_source" is set
# to 2; our CLI always drives the NIST AES-CTR DRBG (randombytes) instead, so the
# call is never executed. Replace the missing symbol with a constant via a -D
# macro (returns 1 so the upstream assert is satisfied) rather than editing the
# upstream source.
gcc -O2 -fcommon -D'FIPS_mode_set(x)=1' -o cli \
    cli.c gfext_poly_gf2.c gui.c gui_sig.c hash_utils.c prng_utils.c rng.c sign.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
