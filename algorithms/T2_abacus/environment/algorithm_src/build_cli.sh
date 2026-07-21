#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Abacus sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Abacus.zip
unzip Abacus.zip

# Copy reference implementation source files.
# The reference implementation folder name contains a space
# ("Reference Implementation"), so we quote it.
cp "Abacus/Reference Implementation/Abacus_Reference.c" \
   "Abacus/Reference Implementation/Abacus_Reference.h" \
   .

# Compile the CLI.
# Abacus_Reference.h provides the standard NIST SHA-3 API (Hash, Init,
# Update, Final). It lacks include guards, so we do NOT use -include;
# cli.c's own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) match the NIST API.
gcc -O3 -std=c99 -o cli \
    cli.c Abacus_Reference.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
