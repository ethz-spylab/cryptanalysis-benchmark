#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract DynamicSHA_2 sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/DynamicSHA_2.zip
unzip DynamicSHA_2.zip

# Copy reference implementation header file
# Note: DynamicSHA_2 is a header-only implementation — dsha2_Ref.h contains
# both declarations and the full Hash/Init/Update/Final implementation.
# genKAT_ref.c is the KAT generator with its own main(), so we skip it.
cp "DynamicSHA_2/Reference Implementation/dsha2_Ref.h" .

# Compile the CLI
# Since the implementation is header-only, we only compile cli.c and include
# dsha2_Ref.h via -include to provide the Hash() function.
# -D_POSIX_C_SOURCE is needed because -include processes dsha2_Ref.h (which
# includes <stdlib.h>) BEFORE cli.c's own #define _POSIX_C_SOURCE, which would
# cause ssize_t/getline to be missing from later headers.
gcc -O3 -std=c99 -o cli \
    cli.c \
    -include dsha2_Ref.h \
    -DHASH_API_ALREADY_INCLUDED \
    -D_POSIX_C_SOURCE=200809L \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
