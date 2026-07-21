#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract McNie sources
unzip -o McNie.zip

# Install necessary dependencies (self-contained AES rng; libssl only for safety)
apt-get update
apt-get install -y libssl-dev

# Chosen parameter set: 3Q_128_1 (smallest public key, NIST category-1 / 128-bit).
PARAM_DIR="McNie/Reference_Implementation/encrypt/3Q_128_1"

# Copy all C sources/headers for the chosen parameter set into the build dir.
cp "$PARAM_DIR"/*.c "$PARAM_DIR"/*.h .

# Remove the NIST KAT harness (it contains the upstream main()).
rm -f KAT_encrypt.c PQCgenKAT_encrypt.c

# Compile the CLI. McNie ships its own AES (aes256.c) and NIST DRBG (rng.c),
# so no OpenSSL linkage is required. -fcommon tolerates legacy tentative defs.
gcc -O3 -fcommon -I. -o cli \
    cli.c aes256.c bin_vec.c conv.c crypt.c gf.c matrix.c rng.c sha3.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
