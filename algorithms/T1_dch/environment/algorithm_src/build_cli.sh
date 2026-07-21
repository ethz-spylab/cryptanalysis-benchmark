#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract DCH sources
# csrc.nist.rip currently returns 500 for this file; fall back to the
# Wayback Machine snapshot of the original NIST URL.
# wget --tries=5 --waitretry=10 --retry-connrefused -O DCH.zip "https://web.archive.org/web/20101105154149if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/DCH.zip"
unzip DCH.zip

# Copy reference implementation source files
cp DCH/Reference_Implementation/dch.c \
   DCH/Reference_Implementation/dch.h \
   .

# Compile the CLI
# dch.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include dch.h here because dch.h lacks include guards and
# dch.c already includes it, which would cause redefinition errors.
# Instead, cli.c uses its own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) which match the NIST API types.
gcc -O3 -std=c99 -o cli \
    cli.c dch.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
