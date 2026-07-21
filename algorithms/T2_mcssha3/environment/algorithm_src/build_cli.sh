#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract MCSSHA-3 sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/MCSSHA3.zip
unzip MCSSHA3.zip

# Copy reference implementation source files. The folder name contains a
# space ("Reference Implementation"), so we quote it.
cp "MCSSHA3/Reference Implementation/mcssha3.c" \
   "MCSSHA3/Reference Implementation/mcssha3.h" \
   .

# Compile the CLI.
# mcssha3.h provides the standard NIST SHA-3 API (Hash, Init, Update,
# Final) and has proper include guards. We do NOT use -include because
# cli.c's own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) already match the NIST API.
# mcssha3.c calls memcpy without including <string.h>, so we force-include
# it to silence the implicit-declaration warning.
gcc -O3 -std=c99 -D_POSIX_C_SOURCE=200809L -include string.h -o cli \
    cli.c mcssha3.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
