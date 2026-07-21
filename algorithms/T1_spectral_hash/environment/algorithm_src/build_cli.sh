#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Spectral_Hash sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Spectral_Hash.zip
unzip Spectral_Hash.zip

# Copy reference implementation source files
cp Spectral_Hash/REFERENC/SHASH.C \
   Spectral_Hash/REFERENC/SHASH.H \
   .

# Fix case sensitivity: SHASH.C includes "shash.h" (lowercase) but the actual
# file is "SHASH.H" (uppercase). On case-sensitive Linux filesystems this
# would fail to compile, so we rename the files to lowercase.
mv SHASH.C shash.c
mv SHASH.H shash.h

# Fix __uint64_t type conflict: both shash.h and shash.c try to typedef __uint64_t
# as "unsigned long long", but on Linux <bits/types.h> (pulled in by <stdio.h>)
# already defines it as "unsigned long int". The #ifdef/#ifndef guards don't help
# because __uint64_t is a typedef, not a macro, so the preprocessor can't detect it.
# Solution: remove the redundant typedef blocks from both files since the system
# already provides these types via <bits/types.h>.
sed -i '/#ifdef __uint8_t/,/#endif/d' shash.h
sed -i '/#ifdef __uint64_t/,/#endif/d' shash.h
sed -i '/#ifndef __uint8_t/,/#endif/d' shash.c
sed -i '/#ifndef __uint64_t/,/#endif/d' shash.c

# Compile the CLI
# shash.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include because the header lacks include guards and
# shash.c already includes it, which would cause redefinition errors.
gcc -O3 -std=c99 -o cli \
    cli.c shash.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
