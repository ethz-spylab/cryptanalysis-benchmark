#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Shabal sources (Round 2 submission).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round2/documents/Shabal_Round2.zip
unzip Shabal_Round2.zip

# Copy reference implementation source files.
cp Shabal/Reference_Implementation/shabal.c \
   Shabal/Reference_Implementation/shabal.h \
   .

# Compile the CLI.
# shabal.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c shabal.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
