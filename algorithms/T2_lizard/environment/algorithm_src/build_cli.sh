#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Lizard sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Lizard.zip
unzip -o Lizard.zip

# We build the *KEM* (Lizard.KEM tree, standard NIST crypto_kem_keypair/enc/dec).
# The smallest parameter set is KEM_CATEGORY1_N536 (LWE_N = 536), which is the
# default already selected in params.h — no upstream edit needed.
SRC="NISTLizardFinal/Reference_Implementation/Lizard.KEM"

# Copy all source and header files from the chosen KEM parameter tree
cp "$SRC"/*.c .
cp "$SRC"/*.h .

# Remove the upstream KAT/benchmark driver (it has its own main())
rm -f main.c

# Lizard.c does #include <libkeccak.a.headers/SP800-185.h> (XKCP), which is not
# packaged in Ubuntu apt repos. (The include is the only keccak reference; all
# hashing is actually done via the vendored sha512.c, so nothing links against
# keccak symbols — but the header must exist to compile.) Build libkeccak.a from
# the vendored XKCP sources and install headers + lib into /usr/local.
apt-get update
apt-get install -y xsltproc build-essential libssl-dev

if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  # Upstream renamed libkeccak.a -> libXKCP.a; install under both the legacy
  # name and include path so the upstream -I.../libkeccak.a.headers include works.
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
fi

# Compile the CLI. -fcommon avoids multiple-definition errors from the upstream
# header (Lizard.h declares clock_t globals in a header included by several .c).
gcc -O2 -fcommon -o cli \
    cli.c Lizard.c randombytes.c sha512.c \
    -I. -I/usr/local/include \
    -L/usr/local/lib -lkeccak -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
