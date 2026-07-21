#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract RVB sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/RVB.zip
unzip RVB.zip
unzip RVB/Reference_Implementation/rvb_reference_c.zip

# Install necessary dependencies
apt-get update
apt-get install -y libgmp-dev libssl-dev

# Build MPFR from source (included in the reference implementation)
MPFR_INSTALL_DIR="$SCRIPT_DIR/mpfr_install"
cd rvb_reference_c/mpfr
if [ ! -f "$MPFR_INSTALL_DIR/lib/libmpfr.a" ]; then
    ./configure --prefix="$MPFR_INSTALL_DIR"
    make
    make install
fi
cd "$SCRIPT_DIR"

# Copy source files from rvb_reference_c to the current directory
# (excluding PQCgenKAT_kem.c which has its own main function)
cp rvb_reference_c/kem.c rvb_reference_c/rng.c rvb_reference_c/sha3.c .
cp rvb_reference_c/*.h .

# Copy the mpfr directory (needed for header includes - kem.c uses "./mpfr/src/mpfr.h")
cp -r rvb_reference_c/mpfr .

# Compile the CLI
# Source files: cli.c, kem.c, rng.c, sha3.c
# Libraries: GMP, MPFR (local), OpenSSL
gcc -O3 -o cli \
    cli.c kem.c rng.c sha3.c \
    -I. -I"$MPFR_INSTALL_DIR/include" \
    -L"$MPFR_INSTALL_DIR/lib" \
    -lmpfr -lgmp -lssl -lcrypto \
    -Wl,-rpath,"$MPFR_INSTALL_DIR/lib"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"

# Clean up downloaded archives
# rm -rf RVB.zip RVB
