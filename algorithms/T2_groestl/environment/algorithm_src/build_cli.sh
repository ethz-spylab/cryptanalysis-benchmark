#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Grøstl sources (Round 3 final submission).
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20120813if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round3/documents/Groestl_FinalRnd.zip"
unzip Groestl_FinalRnd.zip

# Copy reference implementation source files.
cp Groestl_FinalRnd/Reference_Implementation/Groestl-ref.c \
   Groestl_FinalRnd/Reference_Implementation/Groestl-ref.h \
   Groestl_FinalRnd/Reference_Implementation/brg_types.h \
   .

# Compile the CLI.
# Groestl-ref.h provides the NIST SHA-3 API with include guards; cli.c
# uses its own fallback extern declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c Groestl-ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
