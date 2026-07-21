#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract MD6 sources (archive expands to MD6/...)
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/MD6Update.zip
unzip -o md6.zip

REF="MD6/Reference_Implementation"

# Copy the reference implementation modules that Hash() needs:
#   md6_nist.c -> Hash/Init/Update/Final (standard NIST SHA-3 API)
#   md6_mode.c, md6_compress.c -> the MD6 core
# plus the MD6 headers (md6.h, md6_nist.h).
#
# We deliberately do NOT copy the upstream inttypes.h / stdint.h: those are
# MSVC-only shims ("#error Use this header only with Microsoft Visual C++").
# Under gcc, md6.h falls back to the system <inttypes.h>; copying the shims and
# adding -I. would shadow the real headers and break the build.
cp "$REF/md6_nist.c" \
   "$REF/md6_mode.c" \
   "$REF/md6_compress.c" \
   "$REF/md6.h" \
   "$REF/md6_nist.h" \
   .

# Compile the CLI.
# cli.c forward-declares the NIST SHA-3 API itself, so we do NOT use -include;
# the Hash symbol is resolved from md6_nist.c at link time.
# -fcommon allows the upstream tentative globals to merge across translation
# units (newer GCC defaults to -fno-common, which trips on MD6's globals).
gcc -O3 -std=c99 -fcommon -o cli \
    cli.c md6_nist.c md6_mode.c md6_compress.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
