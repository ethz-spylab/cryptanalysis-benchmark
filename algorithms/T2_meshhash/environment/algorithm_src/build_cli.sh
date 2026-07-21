#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract MeshHash sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/MeshHash.zip
unzip MeshHash.zip

# Copy reference implementation source files
cp MeshHash/Reference_Implementation/meshhash.c \
   MeshHash/Reference_Implementation/meshhash.h \
   .

# Compile the CLI
# meshhash.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include because the header lacks include guards and
# meshhash.c already includes it, which would cause redefinition errors.
gcc -O3 -std=c99 -o cli \
    cli.c meshhash.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
