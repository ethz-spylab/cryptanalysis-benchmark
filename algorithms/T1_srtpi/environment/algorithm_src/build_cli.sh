#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SRTPI sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/SRTPI.zip
unzip SRTPI.zip


# Install necessary dependencies
apt-get update
apt-get install -y libssl-dev

# Copy source files from SRTPI to the current directory
cp SRTPI/Reference_Implementaion/encrypt/* .

# Compile the CLI
# Source files: cli.c, kem.c, rng.c, sha3.c
# Libraries: OpenSSL
gcc -O3 -o cli encrypt.c rng.c cli.c -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"

# Clean up downloaded archives
# rm -rf SRTPI.zip SRTPI
