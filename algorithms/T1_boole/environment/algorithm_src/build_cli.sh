#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract BOOLE sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/BOOLE.zip
unzip boole.zip

# Copy reference implementation source files
cp BOOLE/Reference_Implementation/Boole.c \
   BOOLE/Reference_Implementation/Boole.h \
   .

# Compile the CLI
# Boole.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include Boole.h here because Boole.c already includes it,
# which would cause redefinition errors. Instead, cli.c uses its own fallback
# extern declarations (behind #ifndef HASH_API_ALREADY_INCLUDED) which match
# the NIST API types.
gcc -O3 -std=c99 -o cli \
    cli.c Boole.c \
    -DWORDSIZE=32 \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
