#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Hamsi sources (Round 2 package). The archive contains a top-level
# Hamsi/ directory with the reference implementation under
# Hamsi/Reference_Implementation/.
unzip -o hamsi.zip

# Copy reference implementation source files implementing the NIST SHA-3 API.
# - nist-wrapper.c : provides Hash/Init/Update/Final (the standard NIST API)
# - i.hamsi-ref.c  : core permutation (hash256/hash512, subst, Mix, diffuse)
# - hamsi-exp.c    : message-expansion tables T256/T512 (large)
# - hamsi-tables.c : round constants (alpha) and IVs
# Plus the required headers. genKAT.c is deliberately NOT copied because it
# defines its own main().
cp Hamsi/Reference_Implementation/nist-wrapper.c \
   Hamsi/Reference_Implementation/i.hamsi-ref.c \
   Hamsi/Reference_Implementation/hamsi-exp.c \
   Hamsi/Reference_Implementation/hamsi-tables.c \
   Hamsi/Reference_Implementation/nist.h \
   Hamsi/Reference_Implementation/hamsi.h \
   Hamsi/Reference_Implementation/hamsi-tables.h \
   Hamsi/Reference_Implementation/hamsi-internals.h \
   Hamsi/Reference_Implementation/words.h \
   .

# Compile the CLI.
# nist.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
# We do NOT use -include because nist.h is already included by nist-wrapper.c
# and cli.c carries its own fallback extern declarations for the NIST API.
gcc -O3 -std=c99 -o cli \
    cli.c nist-wrapper.c i.hamsi-ref.c hamsi-exp.c hamsi-tables.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
