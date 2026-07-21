#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract GuessAgain sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Hila5.zip
unzip Hila5.zip

# Install necessary dependencies
apt-get update

# Copy source files from Reference_Implementation to the current directory
cp Reference_Implementation/* .

# Compile the CLI
gcc -std=c99 -Wall -Ofast -I. -o cli cli.c hila5_sha3_ref.c kem.c -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"

# Clean up downloaded archives
# rm -rf Hila5.zip Additional_Implementations KAT Optimized_Implementation Reference_Implementation Supporting_Documentation LICENSE README
