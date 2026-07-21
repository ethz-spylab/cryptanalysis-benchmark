#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Unpack the upstream LIMA round-1 submission package.
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Lima.zip
unzip -o Lima.zip

# LIMA's xof.c/xof.h include <libkeccak.a.headers/SP800-185.h> (KMAC256) from
# XKCP, which is not packaged in Ubuntu apt repos. Build libkeccak.a from the
# vendored XKCP sources and install headers+lib into /usr/local under the legacy
# (libkeccak.a) name so the upstream -lkeccak / -I.../libkeccak.a.headers
# references keep working without editing upstream.
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

# Variant: smallest parameter set, Lima_sp__1018 (safe-prime, dimension 1018),
# from the CCA-secure encapsulation (KEM) tree NIST/EncapCCA.
REF="Lima/Reference_Implementation"
LIB="$REF/Lib"
KEM="$REF/NIST/EncapCCA"

# Copy the LIMA library sources/headers and the chosen KEM tree next to cli.c.
cp "$LIB"/*.c "$LIB"/*.h .
cp "$KEM"/api.h "$KEM"/kem.c "$KEM"/rng.c "$KEM"/rng.h .

# Compile the CLI.
#   -DLIMASZ=1018 selects the Lima_sp__1018 parameter set in api.h.
#   -lkeccak  -> XKCP KMAC256 (xof.c)
#   -lcrypto  -> OpenSSL AES-CTR DRBG used by rng.c
#   -lm       -> math (fft.c)
#   -fcommon tolerates the upstream's tentative globals.
gcc -O2 -fcommon -std=c11 -DLIMASZ=1018 \
    -I. -I/usr/local/include \
    cli.c kem.c rng.c \
    fft.c lima.c modp.c xof.c LimaAPI.c \
    -L/usr/local/lib -lkeccak -lcrypto -lm \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
