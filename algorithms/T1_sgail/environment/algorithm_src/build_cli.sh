#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract sgail sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/sgail.zip
unzip sgail.zip

# Copy reference implementation source files
cp sgail/Reference_Implementation/nist_v3.c \
   sgail/Reference_Implementation/nist_v3.h \
   sgail/Reference_Implementation/nist_v3__tables.c \
   .

# Compile the CLI
# nist_v3.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include because the header lacks include guards and
# nist_v3.c already includes it, which would cause redefinition errors.
gcc -O3 -std=c99 -o cli \
    cli.c nist_v3.c nist_v3__tables.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
