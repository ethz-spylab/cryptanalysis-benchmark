#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SHAMATA sources
# csrc.nist.rip currently returns 500 for this file; fall back to the
# Wayback Machine snapshot of the original NIST URL.
# wget --tries=5 --waitretry=10 --retry-connrefused -O SHAMATA.zip "https://web.archive.org/web/20101105224019if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/SHAMATA.zip"
unzip SHAMATA.zip

# Copy reference implementation source files
cp "SHAMATA Tubitak UEKAE/Reference Implementation/ShamataReference.c" \
   "SHAMATA Tubitak UEKAE/Reference Implementation/ShamataReference.h" \
   .

# Compile the CLI
# ShamataReference.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include because the header lacks include guards and
# ShamataReference.c already includes it, which would cause redefinition errors.
gcc -O3 -std=c99 -o cli \
    cli.c ShamataReference.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
