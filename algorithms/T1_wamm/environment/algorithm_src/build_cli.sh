#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract WaMM sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/WaMM.zip
unzip WaMM.zip

# Copy reference implementation source files
# The implementation lives in a deeply nested folder structure.
# We skip genKAT.c, main.c, TestBitArray.c, TestHashing.c (test/KAT files with main()).
WAMM_SRC="WaMM/Reference_Implementation/WaMM_Ref/WaMM_Ref"

# Source files
cp "$WAMM_SRC/SHA3API.c" \
   "$WAMM_SRC/WaMM.c" \
   "$WAMM_SRC/WaMMOperator.c" \
   "$WAMM_SRC/WaMMTappingPrimes.c" \
   "$WAMM_SRC/BitArray.c" \
   "$WAMM_SRC/ReverseBits.c" \
   "$WAMM_SRC/WaMMErrorMessage.c" \
   .

# Header files
cp "$WAMM_SRC/SHA3API.h" \
   "$WAMM_SRC/WaMM.h" \
   "$WAMM_SRC/WaMMOperator.h" \
   "$WAMM_SRC/WaMMTappingPrimes.h" \
   "$WAMM_SRC/WaMMConstants.h" \
   "$WAMM_SRC/BitArray.h" \
   "$WAMM_SRC/ReverseBits.h" \
   "$WAMM_SRC/WaMMErrorMessage.h" \
   .

# Note: WaMM's SHA3API.h uses BAD_HASHLENGTH (value 2) in its HashReturn enum
# instead of the NIST-standard BAD_HASHBITLEN. The CLI only checks for SUCCESS,
# so this enum name difference does not affect functionality. The -include flag
# ensures SHA3API.h is included before cli.c's fallback declarations.

# Compile the CLI
gcc -O3 -std=c99 -o cli \
    cli.c SHA3API.c WaMM.c WaMMOperator.c WaMMTappingPrimes.c \
    BitArray.c ReverseBits.c WaMMErrorMessage.c \
    -include SHA3API.h \
    -DHASH_API_ALREADY_INCLUDED \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
