#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Odd Manhattan sources
unzip -o Odd_Manhattan.zip

# Use the Reference_Implementation, smallest / primary parameter set (128-bit
# security). Upstream ships the 128-bit set as the active api.h already
# (api.h == api.h.128), so we copy the sources as-is.
SRC_DIR="$SCRIPT_DIR/Odd_Manhattan/Reference_Implementation"
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Select the 128-bit parameter set explicitly (smallest real set) by overwriting
# api.h with api.h.128. They are byte-identical upstream, but be explicit so the
# build is robust if the active api.h ever changes.
cp "$SRC_DIR/api.h.128" api.h

# Remove the KAT generation file (has its own main)
rm -f PQCgenKAT_kem.c

# Install build dependencies:
#   - libgmp-dev : kem.c uses GMP big integers (#include "gmp.h", -lgmp)
#   - libssl-dev : NIST rng.c AES-CTR DRBG uses OpenSSL (-lcrypto)
apt-get update
apt-get install -y libgmp-dev libssl-dev

# Compile the CLI. -fcommon avoids multiple-definition errors from legacy
# tentative globals; -I. lets quoted includes ("api.h", "rng.h") resolve here.
gcc -O2 -fcommon -o cli \
    cli.c kem.c rng.c \
    -I. -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
