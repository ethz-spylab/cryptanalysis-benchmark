#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract RLCE sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/RLCE.zip
unzip -o RLCE.zip

# Use the smallest parameter set (lowest security category, smallest keys):
# RLCE_KEM_128A (PK 118441 B, SK 179946 B, ct 785 B).
SRC_DIR="RLCE/Reference_Implementation/RLCE_KEM_128A"

# Copy all source and header files for the chosen parameter set.
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Remove the files that ship their own main() (KAT/example harnesses).
rm -f PQCgenKAT_kem.c NISTexample.c

# Install necessary dependencies (OpenSSL for rng.c / drbg.c AES-CTR DRBG).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. RLCE uses OpenSSL (-lcrypto) and libm (-lm). -fcommon keeps
# legacy tentative-definition behavior so upstream globals do not collide.
gcc -O2 -fcommon -o cli \
    cli.c reedsolomon.c GaloisField.c fieldPoly.c fieldMatrix.c \
    sha.c drbg.c rlce.c aes.c kem.c rng.c \
    -I. -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
