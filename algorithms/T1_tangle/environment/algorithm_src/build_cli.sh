#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Tangle sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Tangle.zip
unzip Tangle.zip

# Copy reference implementation source files
# genKAT.c has its own main(), so we skip it.
cp Tangle/Reference_Implementation/tangle-ref.c \
   Tangle/Reference_Implementation/tangle.h \
   .

# Compile the CLI
# tangle.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include because the header lacks include guards and
# tangle-ref.c already includes it, which would cause redefinition errors.
gcc -O3 -std=c99 -o cli \
    cli.c tangle-ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
