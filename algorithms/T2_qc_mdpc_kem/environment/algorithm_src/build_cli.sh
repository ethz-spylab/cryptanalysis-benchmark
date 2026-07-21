#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Unpack the upstream QC-MDPC KEM round-1 package.
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/QC_MDPC_KEM.zip
unzip -o QC_MDPC_KEM.zip

# Upstream kem.c includes <libkeccak.a.headers/SP800-185.h> (cSHAKE256) from
# XKCP, which is not packaged in Ubuntu apt repos. Build libkeccak.a from the
# vendored XKCP sources and install headers+lib into /usr/local under both the
# new (libXKCP.a) and legacy (libkeccak.a) names so the upstream -lkeccak /
# -I.../libkeccak.a.headers references keep working without editing upstream.
apt-get update
apt-get install -y libssl-dev xsltproc git

if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
fi

# The only parameter set provided in Reference_Implementation/ is "mdpc"
# (r=32771, n0=2, w=274, t=264). Copy all of its sources next to the CLI.
SRC_DIR="$SCRIPT_DIR/QC-MDPC KEM - Atsushi Yamada/Reference_Implementation/kem/mdpc"
cp "$SRC_DIR"/*.c "$SRC_DIR"/*.h .
# randombytes.h pulls in "nist/rng.h", so the rng files stay under nist/.
mkdir -p nist
cp "$SRC_DIR"/nist/rng.c "$SRC_DIR"/nist/rng.h nist/

# Remove the KAT generation harness (has its own main()).
rm -f nist/kat_kem.c

# kem.c (and our cli.c) reference the standard NIST crypto_kem_* names. The
# upstream crypto_kem.h / crypto_kem_mdpc.h remap those to the namespaced
# crypto_kem_mdpc_ref_* symbols that kem.c actually defines, so cli.c must be
# compiled with -include crypto_kem.h to pick up the same remapping.
# rng.c uses OpenSSL AES-CTR DRBG (-lcrypto); cSHAKE256 comes from -lkeccak.
# -fcommon tolerates the upstream's tentative globals.
gcc -O3 -fcommon -std=c99 \
    -I. -Inist -I/usr/local/include \
    -include crypto_kem.h \
    cli.c kem.c nist/rng.c \
    -L/usr/local/lib -lkeccak -lcrypto -ldl \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
