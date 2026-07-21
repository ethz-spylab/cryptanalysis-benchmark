#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract CubeHash sources (Round 2 submission).
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20101106032728if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round2/documents/CubeHash_Round2.zip"
unzip CubeHash_Round2.zip

# Copy reference implementation source files.
cp CubeHash/Reference_Implementation/cubehash.c \
   CubeHash/Reference_Implementation/cubehash.h \
   .

# Compile the CLI.
# cubehash.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c cubehash.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
