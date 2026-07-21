#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract TIB3 sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/TIB3.zip
unzip tib3.zip

# Copy reference implementation source files.
# inupfin.c provides the standard NIST SHA-3 API (Hash, Init, Update, Final),
# which dispatches to the per-length modules (inupfin256/512) and their block
# permutation (encrypt256/512). global.h / inupfin.h are the shared headers.
cp TIB3/Reference_Implementation/inupfin.c \
   TIB3/Reference_Implementation/inupfin256.c \
   TIB3/Reference_Implementation/inupfin512.c \
   TIB3/Reference_Implementation/encrypt256.c \
   TIB3/Reference_Implementation/encrypt512.c \
   TIB3/Reference_Implementation/inupfin.h \
   TIB3/Reference_Implementation/global.h \
   .

# Compile the CLI.
# We do NOT use -include: cli.c carries its own fallback forward declaration of
# Hash(), and the upstream global.h re-typedefs uint32_t/uint64_t (which would
# clash with cli.c's <stdint.h>). Keeping the upstream headers out of cli.c's
# translation unit avoids that conflict; they are only seen by the upstream .c
# files. -fcommon allows the upstream tentative-definition globals to merge.
gcc -O3 -std=c99 -fcommon -o cli \
    cli.c inupfin.c inupfin256.c inupfin512.c encrypt256.c encrypt512.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
