#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Unpack the upstream Titanium round-1 package.
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Titanium.zip
unzip -o Titanium.zip

# Install build deps:
#  - libssl-dev: rng.c uses OpenSSL EVP (AES-CTR DRBG) -> -lcrypto
#  - xsltproc, git: needed to build the vendored XKCP (Keccak) library
apt-get update
apt-get install -y libssl-dev xsltproc git

# Upstream keccak.h includes <libkeccak.a.headers/SimpleFIPS202.h> and
# <libkeccak.a.headers/SP800-185.h> and links against -lkeccak. Those headers
# / lib are not in Ubuntu apt repos, so build libkeccak.a from the vendored
# XKCP sources and install under both the legacy (libkeccak.a) name and the
# expected header path so the upstream references keep working without editing
# upstream.
if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
fi

# Chosen parameter set: smallest "real" CCA-secure set, Titanium_CCA_std.
# (The *_toy / *_lite sets are deliberately under-secure and not real
# parameters.) Copy all of its sources next to the CLI.
SRC_DIR="$SCRIPT_DIR/Titanium/Reference_Implementation/Titanium_CCA_std"
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Remove the KAT generation harness (has its own main()).
rm -f PQCgenKAT_kem.c PQCgenKAT_encrypt.c

# kem.c defines the standard NIST crypto_kem_* names that cli.c calls directly.
# rng.c -> OpenSSL AES-CTR DRBG (-lcrypto); SHAKE256 -> vendored libkeccak.
# -fcommon tolerates upstream tentative globals; -lm for FFT/math in product.c.
gcc -O3 -fcommon \
    -I. -I/usr/local/include \
    cli.c encrypt.c fastrandombytes.c kem.c ntt.c pack.c product.c rng.c sampler.c \
    -L/usr/local/lib -lkeccak -lcrypto -lm \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
