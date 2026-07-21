#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Khichidi-1 sources
# wget "https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Khichidi-1.zip"
unzip Khichidi-1.zip

# Copy reference implementation source files
cp "Khichidi-1/Reference Implementation/Khichidi-1/khichidi.c" \
   "Khichidi-1/Reference Implementation/Khichidi-1/khichidi.h" \
   "Khichidi-1/Reference Implementation/Khichidi-1/khichidi_core.c" \
   "Khichidi-1/Reference Implementation/Khichidi-1/khichidi_core.h" \
   "Khichidi-1/Reference Implementation/Khichidi-1/common.h" \
   .

# Patch: Khichidi's common.h defines DataLength as "WORD" (unsigned long, 32-bit)
# instead of the NIST-standard "unsigned long long" (64-bit). The CLI template
# passes 64-bit DataLength values to Hash(), so we must fix this to avoid
# truncation and ABI mismatch.
# We use sed instead of patch because the source files have Windows-style (CRLF)
# line endings which cause patch to fail with "different line endings".
sed -i 's/typedef WORD DataLength/typedef unsigned long long DataLength/' common.h

# Compile the CLI
# khichidi.h (via common.h) provides the standard NIST SHA-3 API
gcc -O3 -std=gnu99 -o cli \
    cli.c khichidi.c khichidi_core.c \
    -include khichidi.h \
    -DHASH_API_ALREADY_INCLUDED \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
