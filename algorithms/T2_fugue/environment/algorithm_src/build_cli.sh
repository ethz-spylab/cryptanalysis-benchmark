#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Fugue sources (Round 2 update, aka "FugueTweak").
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20101106033053if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round2/documents/Fugue_Round2_Update.zip"
unzip Fugue_Round2_Update.zip

# Copy reference implementation source files.
# SHA3api_ref.c wraps the low-level fugue.c core; fugue_t.h is pulled in
# transitively via the .h files. chkKAT.c / speed.c are drivers and are
# not needed for the CLI build.
cp FugueTweak/Reference_Implementation/SHA3api_ref.c \
   FugueTweak/Reference_Implementation/SHA3api_ref.h \
   FugueTweak/Reference_Implementation/fugue.c \
   FugueTweak/Reference_Implementation/fugue.h \
   FugueTweak/Reference_Implementation/fugue_t.h \
   .

# Compile the CLI.
# SHA3api_ref.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c SHA3api_ref.c fugue.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
