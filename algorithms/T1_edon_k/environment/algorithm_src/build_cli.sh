#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract EdonK sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/EdonK.zip
unzip EdonK.zip

# Copy source files from the reference implementation (excluding kat_kem.c which has its own main)
REFDIR=EdonK/Reference_Implementation/edonk128ref
cp "$REFDIR"/rng.c "$REFDIR"/dec.c "$REFDIR"/enc.c \
   "$REFDIR"/gmp_export.c "$REFDIR"/gmp_import.c "$REFDIR"/mpfq_2_128.c \
   .

# Copy all header files
cp "$REFDIR"/*.h .

# Copy the prebuilt libsupercop.a (provides crypto_hash_sha256)
cp "$REFDIR"/libsupercop.a .

# Clean up downloaded archive and extracted directory
# rm -rf EdonK.zip EdonK

# Install necessary dependencies
apt-get update
apt-get install -y libgmp-dev libssl-dev

# Compile the CLI
gcc -O3 -fcommon -I. -o cli \
    cli.c rng.c dec.c enc.c gmp_export.c gmp_import.c mpfq_2_128.c \
    libsupercop.a \
    -lgmp -lcrypto -ldl

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
