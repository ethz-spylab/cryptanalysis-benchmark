#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Sarmal sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Sarmal.zip
unzip Sarmal.zip

# Copy reference implementation source files. sarmal_ref.c includes
# sarmal-tables.h at compile time, so we need to bring that header too.
cp Sarmal/Reference_Implementation/sarmal_ref.c \
   Sarmal/Reference_Implementation/sarmal.h \
   Sarmal/Reference_Implementation/sarmal-tables.h \
   .

# Compile the CLI.
# sarmal.h provides the standard NIST SHA-3 API (Hash, Init, Update,
# Final) and has proper include guards. We do NOT use -include because
# cli.c's own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) already match the NIST API.
gcc -O3 -std=c99 -o cli \
    cli.c sarmal_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
