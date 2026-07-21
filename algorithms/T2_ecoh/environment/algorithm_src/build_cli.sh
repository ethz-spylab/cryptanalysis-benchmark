#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract ECOH sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/ECOH.zip
unzip ECOH.zip

# Copy reference implementation source files.
# We skip ecoh.main.c because it defines its own main() for the NIST KAT
# driver; our cli.c provides main() instead.
cp ECOH/Reference_Implementation/ecoh.c \
   ECOH/Reference_Implementation/ecoh.h \
   ECOH/Reference_Implementation/ecoh.param.c \
   .

# Compile the CLI.
# ecoh.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final)
# and has proper include guards. We do NOT use -include because cli.c's
# own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) already match the NIST API, and
# ecoh.h also defines #define macros (uint, sint) that would otherwise
# leak into cli.c. We pass -D_x64_ so ecoh.h selects the 64-bit limb
# layout that matches an x86_64 build.
gcc -O3 -std=c99 -D_x64_ -o cli \
    cli.c ecoh.c ecoh.param.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
