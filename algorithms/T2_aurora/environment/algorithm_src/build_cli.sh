#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract AURORA sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/AURORA.zip
unzip AURORA.zip

# Copy reference implementation source files
cp AURORA/Reference_Implementation/aurora_ref.c \
   AURORA/Reference_Implementation/aurora_ref.h \
   .

# Compile the CLI.
# aurora_ref.h provides the standard NIST SHA-3 API (Hash, Init, Update,
# Final) and has proper include guards. We do NOT use -include because
# cli.c's own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) already match the NIST API.
gcc -O3 -std=c99 -o cli \
    cli.c aurora_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
