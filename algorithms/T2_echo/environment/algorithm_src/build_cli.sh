#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract ECHO sources (Round 2 submission).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round2/documents/ECHO_Round2.zip
unzip ECHO_Round2.zip

# Copy reference implementation source files.
cp ECHO/Reference_Implementation/echo_ref.c \
   ECHO/Reference_Implementation/echo.h \
   .

# Compile the CLI.
# echo.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c echo_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
