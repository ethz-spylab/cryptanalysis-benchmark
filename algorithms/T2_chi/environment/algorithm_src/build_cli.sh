#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract CHI sources (Round 1 update).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/CHIUpdate.zip
unzip CHIUpdate.zip

# Copy reference implementation source files. genKAT.c is a KAT driver
# and is not needed for the CLI build.
cp CHI/Reference_Implementation/chi.c \
   CHI/Reference_Implementation/chi-common.c \
   CHI/Reference_Implementation/chi.h \
   .

# Compile the CLI.
# chi.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c chi.c chi-common.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
