#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract SIMD sources (Round 2 package). The archive contains a top-level
# SIMD/ directory with the portable C reference implementation under
# SIMD/Reference_Implementation/ (the Optimized_* and Additional_* trees use
# SSE/altivec/asm and are deliberately NOT used here).
unzip -o simd.zip

# Copy the portable reference implementation source files implementing the
# NIST SHA-3 API.
# - nist.c      : provides Hash/Init/Update/Final (the standard NIST API)
# - reference.c : core SIMD compression / FFT (portable C, no SSE/asm)
# Plus the required headers:
# - nist.h      : NIST API prototypes + hashState (includes compat.h)
# - compat.h    : cross-platform integer types / rotation helpers
# - simd_iv.h   : initial-vector tables (included by nist.c)
# speed.c is deliberately NOT copied because it defines its own main().
# tables.h is only used by the optimized implementations and is not included
# by the reference sources, so it is not needed.
cp SIMD/Reference_Implementation/nist.c \
   SIMD/Reference_Implementation/reference.c \
   SIMD/Reference_Implementation/nist.h \
   SIMD/Reference_Implementation/compat.h \
   SIMD/Reference_Implementation/simd_iv.h \
   .

# Compile the CLI.
# nist.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final) and
# is already included by nist.c, so we do NOT use -include; cli.c carries its
# own fallback extern declarations for the NIST API.
# -fgnu89-inline : the reference uses GNU89 inline semantics (matches upstream
#                  Makefile) so inline helpers don't cause link errors under C99.
# -D_XOPEN_SOURCE=600 : required by the reference sources (matches upstream).
gcc -O3 -std=c99 -fgnu89-inline -D_XOPEN_SOURCE=600 -o cli \
    cli.c nist.c reference.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
