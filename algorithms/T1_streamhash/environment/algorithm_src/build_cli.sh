#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract StreamHash sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/StreamHash.zip
unzip streamhash.zip

# Copy reference implementation source files
cp StreamHash/Reference_Implementation/streamhash_reference.c \
   StreamHash/Reference_Implementation/streamhash_reference.h \
   StreamHash/Reference_Implementation/sbox32.h \
   .

# Compile the CLI
# streamhash_reference.h provides the standard NIST SHA-3 API
# (Hash, Init, Update, Final). We do NOT use -include because cli.c
# already declares the API itself and streamhash_reference.c includes
# its own header, which would cause redefinition errors.
gcc -O3 -std=c99 -o cli \
    cli.c streamhash_reference.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
