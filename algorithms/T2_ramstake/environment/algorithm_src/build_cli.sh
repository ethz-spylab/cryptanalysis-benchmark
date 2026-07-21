#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract the Ramstake submission package.
unzip -o Ramstake.zip

# Smallest parameter set: Ramstake RS 216091 (over the larger RS 756839).
SRC_DIR="$SCRIPT_DIR/ramstake/Reference_Implementation/Ramstake_RS_216091"

# Copy every .c / .h of the chosen parameter set next to the CLI.
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Remove the KAT generation harness (has its own main()).
rm -f PQCgenKAT_kem.c

# Install build dependencies:
#   - libgmp-dev: big-integer arithmetic over the Mersenne prime (mpz_*)
#   - libssl-dev: AES-256-CTR DRBG in rng.c
#   - xsltproc, git: required by the XKCP build below
apt-get update
apt-get install -y libgmp-dev libssl-dev xsltproc git

# Ramstake's csprng.c / ramstake.c include <libkeccak.a.headers/SimpleFIPS202.h>
# and <libkeccak.a.headers/KeccakHash.h> from XKCP, which is not packaged in
# Ubuntu apt repos. Build libkeccak.a from the vendored XKCP sources and install
# headers+lib into /usr/local under the legacy libkeccak name so the upstream
# -lkeccak / -I.../libkeccak.a.headers references keep working unmodified.
if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
fi

# Compile the CLI. -DKAT is intentionally omitted: with KAT defined, kem.c calls
# ramstake_keygen/encaps/decaps with verbosity 2, which dumps intermediate
# secret state (including the shared secret) to stdout, leaking it through the
# oracle response. -fcommon tolerates the upstream's tentative globals.
# -lgmp for GMP, -lcrypto for OpenSSL rng, -lkeccak for SHA3/SHAKE.
gcc -O2 -std=c99 -fcommon -o cli \
    cli.c \
    csprng.c gf256x.c ramstake.c reedsolomon.c codec_rs.c kem.c rng.c \
    -I. -I/usr/local/include \
    -L/usr/local/lib -lkeccak -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
