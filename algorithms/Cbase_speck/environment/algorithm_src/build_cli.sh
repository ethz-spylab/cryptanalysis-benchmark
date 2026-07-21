#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract simon-speck sources
# wget https://nsacyber.github.io/simon-speck/implementations/code/supercop/simon-speck.zip
unzip simon-speck.zip

# Upstream SUPERCOP ships no Speck 32/64 (its smallest block is 64 bits). We
# start from the 64/128 reference -- which already has the 4-key-word schedule
# that 32/64 requires -- and apply speck3264.patch to retarget it to 16-bit
# words, 22 rounds and the alpha=7/beta=2 rotations unique to 32/64. Verified
# against the SIMON/SPECK spec test vector (key 1918 1110 0908 0100,
# pt 6574 694c -> ct a868 42f2).
cp crypto_stream/speck64128ctr/ref/stream.c .
patch -p1 < speck3264.patch

# Compile the CLI
gcc -O3 -o cli cli.c stream.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
