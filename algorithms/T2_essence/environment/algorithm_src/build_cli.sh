#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract ESSENCE sources
unzip -o ESSENCE.zip

# Copy reference implementation source files. The upstream directory path
# contains spaces and dashes ("CD - UNIX EOL"), so all paths are quoted.
cp "ESSENCE/CD - UNIX EOL/Reference_Implementation/essence_api.c" \
   "ESSENCE/CD - UNIX EOL/Reference_Implementation/essence_compress_512.c" \
   "ESSENCE/CD - UNIX EOL/Reference_Implementation/essence_compress_256.c" \
   "ESSENCE/CD - UNIX EOL/Reference_Implementation/essence_L_tables.c" \
   "ESSENCE/CD - UNIX EOL/Reference_Implementation/essence.h" \
   "ESSENCE/CD - UNIX EOL/Reference_Implementation/essence_api.h" \
   .

# Compile the CLI.
# essence_api.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# Upstream Makefile uses -O3 -ansi; we use -O3 -std=c99 instead.
gcc -O3 -std=c99 -o cli \
    cli.c essence_api.c essence_compress_512.c essence_compress_256.c essence_L_tables.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
