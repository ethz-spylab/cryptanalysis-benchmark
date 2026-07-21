#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract CRUNCH sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/CRUNCH.zip
unzip crunch.zip

# Copy reference implementation source files.
# The generic NIST SHA-3 API (Hash, Init, Update, Final) lives in
# crunch_main.c, which dispatches to the per-digest-length modules
# crunch_224.c / crunch_256.c / crunch_384.c / crunch_512.c. Those modules
# share the precomputed constant table in const_64.c (selected via -DM64).
REF="CRUNCH/Reference_implementation"
cp "$REF/crunch_main.c" \
   "$REF/crunch_224.c" "$REF/crunch_256.c" \
   "$REF/crunch_384.c" "$REF/crunch_512.c" \
   "$REF/const_64.c" \
   "$REF/crunch.h" "$REF/crunch_type.h" \
   "$REF/crunch_224.h" "$REF/crunch_256.h" \
   "$REF/crunch_384.h" "$REF/crunch_512.h" \
   .

# Compile the CLI.
# crunch_type.h provides the standard NIST SHA-3 typedefs and crunch_main.c
# provides the generic Hash() entry point that cli.c forward-declares, so we
# do NOT use -include. -DM64 selects the 64-bit constant table (const_64.c).
#
# -fcommon: the four crunch_<len>.c modules each declare the same tentative
# global state variables (PrevHash, LeftData, SizeLeft, TotalInputSizeInBit)
# without `extern`. Pre-C99 toolchains (and the upstream Makefile) merged
# these into a single common symbol; modern GCC defaults to -fno-common and
# rejects them as multiple definitions. -fcommon restores the original
# behavior without touching the upstream source. Only one digest length is
# ever active per process, so the shared state is harmless.
gcc -O3 -std=gnu99 -fcommon -DM64 -o cli \
    cli.c crunch_main.c crunch_224.c crunch_256.c crunch_384.c crunch_512.c const_64.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
