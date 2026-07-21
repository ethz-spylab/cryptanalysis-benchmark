#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Lilliput-AE sources
unzip -o lilliput-ae.zip

# Reference implementation:
#   Lilliput-AE-II-128 (lilliputaeii128v1) -- the nonce-misuse-resistant
#   (AE-II) mode with the smallest (128-bit) key.
REF=lilliput-ae/Implementations/crypto_aead/lilliputaeii128v1/ref

# Copy the reference C sources (rename encrypt.c to avoid clashing with cli.c
# helpers) and headers needed to compile.
cp "$REF/encrypt.c" algorithm_encrypt.c
cp "$REF/cipher.c" .
cp "$REF/lilliput-ii.c" .
cp "$REF/tweakey.c" .
cp "$REF/api.h" .
cp "$REF/cipher.h" .
cp "$REF/constants.h" .
cp "$REF/parameters.h" .
cp "$REF/tweakey.h" .
cp "$REF/lilliput-ae.h" .
cp "$REF/lilliput-ae-utils.h" .
# crypto_aead.h is the standard NIST LWC API header (vendored alongside cli.c;
# the upstream ref/ directory omits it as it is normally supplied by the test
# harness). It declares crypto_aead_encrypt/decrypt used by both cli.c and
# algorithm_encrypt.c.

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c cipher.c lilliput-ii.c tweakey.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
