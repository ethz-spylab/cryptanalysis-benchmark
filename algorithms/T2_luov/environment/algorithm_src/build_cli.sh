#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Unpack the upstream LUOV round-1 submission package.
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/LUOV.zip
unzip -o LUOV.zip

# Install build deps:
#  - libssl-dev: rng.c uses OpenSSL EVP (AES-CTR DRBG) -> -lcrypto
#  - xsltproc, git: needed to build the vendored XKCP (Keccak) library
apt-get update
apt-get install -y libssl-dev xsltproc git

# Upstream keccakrng.h / Bitcontainer.h include
# <libkeccak.a.headers/KeccakHash.h> and
# <libkeccak.a.headers/KeccakSpongeWidth1600.h> and the Makefile links against
# -lkeccak. Those headers / lib are not in Ubuntu apt repos, so build
# libkeccak.a from the vendored XKCP sources and install it under both the
# legacy (libkeccak.a) name and the expected header path so the upstream
# references keep working without editing upstream.
if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
fi

# Bitcontainer.h includes the legacy Keccak Code Package header name
# <libkeccak.a.headers/KeccakSpongeWidth1600.h>, which modern XKCP no longer
# ships. LUOV only uses the Keccak_Hash* sponge API (the include is otherwise
# unused — no KeccakWidth1600_Sponge* symbol is referenced anywhere in the
# tree), so provide a one-line shim header that forwards to KeccakHash.h. This
# keeps the upstream source unedited.
if [ ! -f /usr/local/include/libkeccak.a.headers/KeccakSpongeWidth1600.h ]; then
  echo '#include "KeccakHash.h"' > /usr/local/include/libkeccak.a.headers/KeccakSpongeWidth1600.h
fi

# Chosen parameter set: luov-8-63-256 (FIELD_SIZE=8, OIL_VARS=63,
# VINEGAR_VARS=256, SHAKE128). This is the smallest-signature NIST level-2 set,
# and is the parameter set already selected (un-commented) in the upstream
# parameters.h, so no -D macro is needed to pick it.
SRC_DIR="$SCRIPT_DIR/LUOV/Reference_Implementation/luov-8-63-256"
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Remove the upstream harnesses that carry their own main().
rm -f PQCgenKAT_sign.c test.c

# Compile the CLI.
#   -DKAT is intentionally omitted: with KAT defined, sign.c / LUOV.c /
#   intermediateValues.c dump intermediate (secret) signing state to stdout,
#   which would leak through the oracle response.
#   rng.c -> OpenSSL AES-CTR DRBG (-lcrypto); SHAKE -> vendored libkeccak.
#   -std=c99 matches the upstream Makefile; -fcommon tolerates tentative globals.
gcc -O2 -std=c99 -fcommon \
    -I. -I/usr/local/include \
    cli.c \
    Bitcontainer.c F8Field.c F16Field.c F32Field.c F48Field.c F64Field.c \
    F80Field.c LUOV.c LinearAlgebra.c buffer.c keccakrng.c rng.c \
    intermediateValues.c sign.c \
    -L/usr/local/lib -lkeccak -lcrypto \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
