#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Luffa sources
# wget https://web.archive.org/web/20170830023437/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/Luffa.zip
unzip -o Luffa.zip

# Copy reference implementation source files (note the SPACE in the directory name).
# genKAT.c has its own main(), so we skip it.
cp "Luffa/Reference Implementation/luffa.c" \
   "Luffa/Reference Implementation/luffa.h" \
   .

# Compile the CLI
# luffa.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# luffa.c already includes luffa.h, so we do NOT use -include.
gcc -O3 -std=c99 -o cli \
    cli.c luffa.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
