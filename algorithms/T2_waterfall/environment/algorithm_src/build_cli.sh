#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Waterfall sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Waterfall.zip
unzip Waterfall.zip

# Copy reference implementation source files
cp Waterfall/Reference_Implementation/Waterfall.c \
   Waterfall/Reference_Implementation/Waterfall.h \
   .

# Compile the CLI
# Waterfall.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include Waterfall.h here because Waterfall.c already includes
# it; cli.c uses its own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) which match the NIST API types.
gcc -O3 -std=c99 -o cli \
    cli.c Waterfall.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
