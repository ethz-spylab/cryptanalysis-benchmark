#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Cheetah sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Cheetah.zip
unzip Cheetah.zip

# Copy reference implementation source files.
# Cheetah.c is self-contained: it includes only Cheetah.h, which provides the
# standard NIST SHA-3 API (Hash, Init, Update, Final) plus all S-boxes/tables.
cp Cheetah/Reference_Implementation/Cheetah.c \
   Cheetah/Reference_Implementation/Cheetah.h \
   .

# Compile the CLI.
# We do NOT use -include: Cheetah.c already includes Cheetah.h, and cli.c
# supplies its own ABI-compatible forward declarations of the NIST SHA-3 API.
gcc -O3 -std=c99 -o cli \
    cli.c Cheetah.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
