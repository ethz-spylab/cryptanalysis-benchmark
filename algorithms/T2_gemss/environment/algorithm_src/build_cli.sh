#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract the GeMSS Round-3 submission package.
# wget https://csrc.nist.gov/CSRC/media/Projects/post-quantum-cryptography/documents/round-3/submissions/GeMSS-Round3.zip
unzip -o GeMSS-Round3.zip

# Install build dependencies:
#  - libssl-dev : rng.c / hash.c use OpenSSL (AES-CTR DRBG, RAND_bytes) -> -lcrypto
#  - libgmp-dev : pulled in by / used alongside the gf2x library
#  - libgf2x-dev: GeMSS sets ENABLED_GF2X 1 in include/arch.h and includes
#                 <gf2x/gf2x_mulN.h> + calls gf2x_mul() -> -lgf2x. Provided by
#                 the Ubuntu package (matches the bundled gf2x-1.2 API).
#  - xsltproc, git : needed to build the vendored XKCP (Keccak) library
apt-get update
apt-get install -y libssl-dev libgmp-dev libgf2x-dev xsltproc git

# GeMSS's hash.h includes <libkeccak.a.headers/SimpleFIPS202.h> and
# <libkeccak.a.headers/KeccakHash.h> and links against -lkeccak (XKCP SHA3 /
# SHAKE). Those headers / lib are not in Ubuntu apt repos, so build libkeccak.a
# from the vendored XKCP sources and install under both the legacy
# (libkeccak.a) name and the expected header path so the upstream references
# keep working without editing upstream.
if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
  # GeMSS-Round3 was written against an OLDER XKCP layout: hash.h does
  #   #include <libkeccak.a.headers/KeccakSpongeWidth1600.h>
  # which the modern XKCP renamed to KeccakSponge.h (the KeccakWidth1600_Sponge
  # function and all Keccak_Hash* symbols GeMSS uses are still provided, just
  # via the renamed header). Install a compatibility shim under the legacy name
  # so the upstream GeMSS #include keeps working WITHOUT editing upstream.
  echo '#include "KeccakSponge.h"' \
      > /usr/local/include/libkeccak.a.headers/KeccakSpongeWidth1600.h
fi

# Chosen variant: GeMSS128 (NIST security level I, the smallest GeMSS set).
SRC_DIR="$SCRIPT_DIR/GeMSS-Round3/Reference_Implementation/sign/GeMSS128"
cp "$SRC_DIR"/src/*.c .
cp "$SRC_DIR"/include/*.h .

# Remove the KAT generation harness (PQCgenKAT_sign.c has its own main()).
rm -f PQCgenKAT_sign.c

# Remove randombytes_FIPS.c: it is an UNUSED alternative RNG (only selected when
# ENABLED_OPENSSL_FIPS=1, but the default is ENABLED_OPENSSL_NORMAL=1 ->
# RAND_bytes). It references FIPS_mode()/FIPS_mode_set(), which were removed in
# OpenSSL 3.x, so linking it fails. It is never called, so dropping it from the
# build is safe (and not an edit to upstream code).
rm -f randombytes_FIPS.c

# Compile the CLI.
#  -I.                      -> upstream headers + cli_stdin.h next to cli.c
#  -I/usr/local/include     -> libkeccak.a.headers
#  -fcommon                 -> tolerate upstream tentative globals (DRBG_ctx)
#  -lkeccak                 -> XKCP SHA3 / SHAKE (hash.c)
#  -lgf2x                   -> gf2x GF(2)[x] multiplication (ENABLED_GF2X 1)
#  -lcrypto                 -> OpenSSL DRBG / RAND_bytes (rng.c, hash.c)
#  -lgmp -ldl -lpthread     -> transitive deps of gf2x / openssl
# The PCLMUL/AVX SIMD blocks in arch.h are all disabled (#if 0), so no
# -march=native / -mpclmul is required and the build is CPU-independent.
gcc -O2 -fcommon \
    -I. -I/usr/local/include \
    *.c \
    -L/usr/local/lib \
    -lkeccak -lgf2x -lcrypto -lgmp -ldl -lpthread \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
