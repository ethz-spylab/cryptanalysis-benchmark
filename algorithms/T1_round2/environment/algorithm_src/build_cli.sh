#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Round2 sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Round2.zip
unzip Round2.zip

# Use the nround2_kem_nd_l1 variant (n-type, no-CCA-decrypt, Level 1 security)
cp Round2/Reference_Implementation/kem/nround2_kem_nd_l1/*.c .
cp Round2/Reference_Implementation/kem/nround2_kem_nd_l1/*.h .

# Remove the KAT generation file (has its own main)
rm -f PQCgenKAT_kem.c

# Install necessary dependencies
apt-get update
apt-get install -y libssl-dev

# hash.c uses <libkeccak.a.headers/SimpleFIPS202.h> and links -lkeccak.
# The DAGS distribution bundles a pre-compiled libkeccak.a and all Keccak headers,
# so we reuse those instead of building KeccakCodePackage from source.
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/DAGS.zip
unzip DAGS.zip -d /tmp/dags_src
# Use the pre-compiled libkeccak.a
cp /tmp/dags_src/DAGS/Reference_Implementation/kem/dags3/libkeccak.a /usr/local/lib/
ldconfig
# Provide libkeccak.a.headers/ directory with SimpleFIPS202.h and companion headers
# Provide keccak/ headers (SimpleFIPS202.h uses relative includes like ../keccak/...)
cp -r /tmp/dags_src/DAGS/Reference_Implementation/kem/dags3/keccak .
# Provide libkeccak.a.headers/ directory expected by the #include path
mkdir -p libkeccak.a.headers
cp /tmp/dags_src/DAGS/Reference_Implementation/kem/dags3/keccak/SimpleFIPS202.h libkeccak.a.headers/

# Clean up DAGS sources — only the keccak headers and library above are needed
rm -rf /tmp/dags_src

# Compile the CLI
gcc -O2 -fcommon -o cli \
    cli.c cca_encrypt.c cca_kem.c cpa_kem.c drng.c hash.c misc.c pack.c \
    parameters.c pst_core.c pst_dem.c pst_encrypt.c rng.c \
    -I. -lssl -lcrypto -lkeccak -L/usr/local/lib

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
