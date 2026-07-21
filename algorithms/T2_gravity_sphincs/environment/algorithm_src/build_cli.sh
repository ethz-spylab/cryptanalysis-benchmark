#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Gravity-SPHINCS sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Gravity_SPHINCS.zip
unzip -o Gravity_SPHINCS.zip

REF="gravity-sphincs/Reference_Implementation"

# Copy the top-level reference sources/headers into the build root, and keep the
# primitives implementation under primitives/ as upstream lays it out (its .c
# files reach the top-level headers via "../<name>.h", which resolves to the
# build root once the top-level headers are copied here).
cp "$REF"/*.c "$REF"/*.h .
mkdir -p primitives
cp "$REF"/primitives/*.c "$REF"/primitives/*.h primitives/

# Remove the benchmark main (bench.c has its own main()).
rm -f bench.c

# Install necessary dependencies (OpenSSL for AES-CTR / SHA256).
apt-get update
apt-get install -y libssl-dev

# cli.c (copied verbatim from T1_racoss) includes "rng.h" and calls
# randombytes_init(); Gravity-SPHINCS instead ships its own randombytes() that
# already seeds from /dev/urandom. Provide a tiny shim so cli.c links unchanged
# without touching upstream sources.
cat > rng.h <<'EOF'
#pragma once
/* Shim for the NIST DRBG init API expected by the shared cli.c.
   Gravity-SPHINCS seeds its own randombytes() from /dev/urandom, so this is a
   no-op kept only for source compatibility. */
void randombytes_init(unsigned char *entropy_input,
                      unsigned char *personalization_string,
                      int security_strength);
EOF
cat > rng_shim.c <<'EOF'
#include "rng.h"
void randombytes_init(unsigned char *entropy_input,
                      unsigned char *personalization_string,
                      int security_strength) {
    (void)entropy_input;
    (void)personalization_string;
    (void)security_strength;
}
EOF

# Compile the CLI for the "S" (smallest) parameter set, taken verbatim from the
# upstream Makefile VERSION_S (smallest secret key and signature).
# We drop upstream's -march=native (portability) and -std=c89 (cli.c needs GNU
# argp). -fcommon avoids tentative-definition clashes; -I. for headers.
gcc -O2 -fcommon -I. \
    -DPORS_k=24 -DMERKLE_h=5 -DGRAVITY_d=1 -DGRAVITY_c=10 \
    -o cli \
    cli.c rng_shim.c randombytes.c gravity.c ltree.c merkle.c pors.c sign.c wots.c batch.c \
    primitives/haraka.c primitives/aes.c primitives/hash.c \
    -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
