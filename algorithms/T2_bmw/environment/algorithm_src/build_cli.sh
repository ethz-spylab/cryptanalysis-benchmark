#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Blue Midnight Wish sources (Round 2 submission).
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20101106032624if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round2/documents/Blue_Midnight_Wish_Round2.zip"
unzip Blue_Midnight_Wish_Round2.zip

# Copy reference implementation source files.
# BlueMidnightWish_ref.c implements the NIST SHA-3 API declared in
# SHA3api_ref.h. genKAT.c / IntermediateValues.c /
# BlueMidnightWish_ref_IntermediateValues.c are KAT / debug drivers and
# are not needed for the CLI build.
cp Blue_Midnight_Wish/Reference_Implementation/BlueMidnightWish_ref.c \
   Blue_Midnight_Wish/Reference_Implementation/SHA3api_ref.h \
   .

# Compile the CLI.
# SHA3api_ref.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c BlueMidnightWish_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
