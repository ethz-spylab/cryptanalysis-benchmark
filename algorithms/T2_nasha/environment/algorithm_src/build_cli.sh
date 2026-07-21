#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract NaSHA sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/NaSHAUpdate.zip
unzip -o NaSHAUpdate.zip

# Copy reference implementation source files.
# Nasha.c implements the standard NIST SHA-3 API (Init, Update, Final, Hash).
# Nasha.h declares it; brg_endian.h / brg_types.h are byte-order helpers it
# includes. All algorithm tables live inside Nasha.c, so no extra .c module.
cp NaSHA/ReferenceImplementation/Nasha.c \
   NaSHA/ReferenceImplementation/Nasha.h \
   NaSHA/ReferenceImplementation/brg_endian.h \
   NaSHA/ReferenceImplementation/brg_types.h \
   .

# Compile the CLI.
# We do NOT use -include: cli.c provides its own forward declarations of the
# NIST SHA-3 API (BitSequence, DataLength, HashReturn, Hash), and Nasha.c
# already includes Nasha.h, so there is no need to inject the header.
gcc -O3 -std=c99 -o cli \
    cli.c Nasha.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
