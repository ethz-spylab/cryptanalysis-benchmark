#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Skein sources (Round 3 final submission).
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20120813004550if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round3/documents/Skein_FinalRnd.zip"
unzip Skein_FinalRnd.zip

# Copy reference implementation source files.
# SHA3api_ref.c implements the NIST SHA-3 API by wrapping the Skein core
# (skein.c / skein_block.c). The brg_* and skein_port headers are utility
# headers pulled in transitively via the .h files.
cp Skein_FinalRnd/Reference_Implementation/SHA3api_ref.c \
   Skein_FinalRnd/Reference_Implementation/SHA3api_ref.h \
   Skein_FinalRnd/Reference_Implementation/skein.c \
   Skein_FinalRnd/Reference_Implementation/skein.h \
   Skein_FinalRnd/Reference_Implementation/skein_block.c \
   Skein_FinalRnd/Reference_Implementation/skein_debug.h \
   Skein_FinalRnd/Reference_Implementation/skein_port.h \
   Skein_FinalRnd/Reference_Implementation/brg_endian.h \
   Skein_FinalRnd/Reference_Implementation/brg_types.h \
   .

# Compile the CLI.
# SHA3api_ref.h has include guards. cli.c uses its own fallback extern
# declarations for the NIST SHA-3 API, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c SHA3api_ref.c skein.c skein_block.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
