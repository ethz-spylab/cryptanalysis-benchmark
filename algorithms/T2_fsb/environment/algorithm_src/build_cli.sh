#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract FSB sources (Round 1 submission).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/FSB.zip
unzip FSB.zip

# Copy reference implementation source files. main.c is a KAT driver
# that defines its own main() and is not needed for the CLI build.
cp FSB/Reference_Implementation/fsb.c \
   FSB/Reference_Implementation/fsb.h \
   FSB/Reference_Implementation/pi.h \
   FSB/Reference_Implementation/nessie.h \
   FSB/Reference_Implementation/Whirlpool.h \
   .

# Compile the CLI.
# fsb.h has no include guards, but cli.c never includes it directly
# (it uses its own fallback extern declarations of the NIST SHA-3 API
# guarded by #ifndef HASH_API_ALREADY_INCLUDED), so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c fsb.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
