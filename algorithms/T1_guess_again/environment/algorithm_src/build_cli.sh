#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract GuessAgain sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/GuessAgain.zip
unzip GuessAgain.zip

# Install necessary dependencies
apt-get update

# Copy source files from Reference_Implementation to the current directory
# (excluding PQCgenKAT_kem.c which has its own main function)
cp GuessAgain/Reference_Implementation/* .

# Compile the CLI
# Note: libgen.c is excluded because it has its own main (library generator tool)
gcc -O3 -o cli cli.c encrypt.c rng.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"

# Clean up downloaded archives
# rm -rf GuessAgain.zip GuessAgain
