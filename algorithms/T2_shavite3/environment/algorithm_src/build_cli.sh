#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SHAvite-3 sources. We use the authors' newer
# Round-2 code/KAT drop ("CODE_KAT_SHAvite"), which is the newest
# published source per sources.txt.
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20101106073037if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round2/documents/CODE_KAT_SHAvite.zip"
unzip CODE_KAT_SHAvite.zip

# Copy reference implementation source files. SHAvite3.c is the only
# translation unit; the other files are headers it (or SHA3api_ref.h)
# pulls in.
cp Reference_Implementation/SHAvite3.c \
   Reference_Implementation/SHA3api_ref.h \
   Reference_Implementation/SHAvite3-256.h \
   Reference_Implementation/SHAvite3-512.h \
   Reference_Implementation/AESround.h \
   Reference_Implementation/portable.h \
   .

# Compile the CLI.
# SHA3api_ref.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c SHAvite3.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
