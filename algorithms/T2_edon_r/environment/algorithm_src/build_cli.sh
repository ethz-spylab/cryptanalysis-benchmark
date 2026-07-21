#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Edon-R sources (the "Update" package is the
# canonical Round-1 submission; the update only adjusts API plumbing).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Edon-RUpdate.zip
unzip Edon-RUpdate.zip

# Copy reference implementation source files. Edon-R_ref.c implements the
# NIST SHA-3 API; SHA3api_ref.h is the matching header.
cp Edon-R/Reference_Implementation/Edon-R_ref.c \
   Edon-R/Reference_Implementation/SHA3api_ref.h \
   .

# Compile the CLI.
# SHA3api_ref.h provides the standard NIST SHA-3 API (Hash, Init, Update,
# Final). We do NOT use -include because cli.c's own fallback extern
# declarations (behind #ifndef HASH_API_ALREADY_INCLUDED) already match
# the NIST API.
gcc -O3 -std=c99 -o cli \
    cli.c Edon-R_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
