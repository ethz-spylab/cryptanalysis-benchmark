#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Twister sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/Twister.zip
unzip -o twister.zip

# Copy reference implementation source files.
# The reference code is C++ (ref_twister.cpp) and provides the standard NIST
# SHA-3 API (Init/Update/Final/Hash) via ref_twister.h, plus the constant
# tables in tables.h (included directly by ref_twister.cpp).
cp Twister/Reference_Implementation/ref_twister.cpp \
   Twister/Reference_Implementation/ref_twister.h \
   Twister/Reference_Implementation/tables.h \
   .

# ref_twister.cpp unconditionally `#include <tchar.h>` (Windows-only) but
# never uses any TCHAR symbols; provide an empty stub on the include path so
# the upstream source compiles unmodified on Linux.
cp tchar_stub.h tchar.h

# Compile:
#   - cli.c            : plain C generic SHA-3 CLI (calls a C-linkage `Hash`)
#   - twister_capi.cpp : exports `extern "C" Hash` matching cli.c's prototype
#   - ref_twister.cpp  : upstream reference implementation
# cli.c uses its own fallback NIST API declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED), so we do NOT inject the upstream header
# into cli.c. g++ links the C and C++ objects together.
gcc -O3 -std=c99 -c -o cli.o cli.c -I.
g++ -O3 -c -o twister_capi.o twister_capi.cpp -I.
g++ -O3 -c -o ref_twister.o ref_twister.cpp -I.
g++ -O3 -o cli cli.o twister_capi.o ref_twister.o

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
