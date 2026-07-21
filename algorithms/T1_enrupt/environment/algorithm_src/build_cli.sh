#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract EnRUPT sources
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/EnRUPT.zip
unzip EnRUPT.zip

# Copy reference implementation source files
# portEnRUPT.h is at the zip root (one level above Reference_Implementation),
# and EnRUPT_ref.h includes it as "../portEnRUPT.h", so we copy it and fix
# the include path to be local.
cp EnRUPT/Reference_Implementation/EnRUPT_ref.c \
   EnRUPT/Reference_Implementation/EnRUPT_ref.h \
   EnRUPT/portEnRUPT.h \
   .

# Fix the include path: EnRUPT_ref.h references "../portEnRUPT.h" but we
# have all files in the same directory now.
sed -i 's|#include "../portEnRUPT.h"|#include "portEnRUPT.h"|' EnRUPT_ref.h

# Fix undefined behavior in the `ir1` round macro.
#
# The reference macro reads the round counter `r` several times in one full
# expression while also mutating it with `r++` in the same expression, with no
# intervening sequence point:
#
#   #define ir1(...) (x[...r...]^=f=rotr(...r...)*9, d[r%P]^=f^x[(H*P/2+P%2+r++)%H])
#
# This is undefined behaviour: the order in which `d[r%P]` (which reads `r`) and
# the `r++` are evaluated is unspecified. gcc -O3 evaluates the d-index using the
# POST-increment value of `r`, which diverges from the reference KAT / sample
# vectors.
#
# Fix: move the increment to its own comma-separated sub-expression at the very
# end of the macro. The comma operators are sequence points, so every read of
# `r` now uses the pre-increment value and the increment happens last. This
# matches the reference behaviour (verified against EnRUPT/KAT_MCT/ShortMsgKAT_256.txt).
sed -i 's|+r++)%H\])|+r)%H], r++)|' EnRUPT_ref.c

# Compile the CLI
# EnRUPT_ref.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We disable MMX/SSE intrinsics to avoid needing -mmmx/-msse flags on all platforms
# by forcing the generic implementation types.
gcc -O3 -std=gnu99 -o cli \
    cli.c EnRUPT_ref.c \
    -include EnRUPT_ref.h \
    -DHASH_API_ALREADY_INCLUDED \
    -DENRUPT32_TYPE=0 -DENRUPT64_TYPE=0 \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
