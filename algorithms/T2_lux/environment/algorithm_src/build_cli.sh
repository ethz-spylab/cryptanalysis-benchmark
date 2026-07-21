#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract LUX sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/LUX.zip
unzip LUX.zip

# Copy reference implementation source files
cp LUX-CD/Reference_Implementation/LUX.c \
   LUX-CD/Reference_Implementation/LUX.h \
   .

# Compile the CLI
# LUX.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include LUX.h here: LUX.h lacks include guards and also
# defines several non-static const tables at file scope, and LUX.c already
# includes it. Letting only LUX.c include the header keeps those table
# definitions in a single translation unit. cli.c uses its own fallback
# extern declarations (behind #ifndef HASH_API_ALREADY_INCLUDED) which
# match the NIST API types.
gcc -O3 -std=c99 -o cli \
    cli.c LUX.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
