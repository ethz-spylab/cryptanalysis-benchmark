#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract upstream Ouroboros-R Round-1 submission package.
unzip -o Ouroboros_R.zip

# Smallest parameter set (128-bit security).
SRC_DIR="$SCRIPT_DIR/Reference_Implementation/ouroboros-r-128"

# Install build dependencies:
#   - libgmp-dev / libntl-dev : rank-metric finite-field arithmetic (ffi/*.cpp)
#   - libssl-dev              : SHA512 (lib/hash) + AES-CTR DRBG (lib/rng)
apt-get update
apt-get install -y libgmp-dev libntl-dev libssl-dev

# Copy the CLI sources next to the upstream tree so api.h / rng.h are visible.
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Remove the upstream KAT harness (it has its own main()).
rm -f src/main_kat.c

# Everything is built with g++ (upstream is C++; cli.c contains no extern "C",
# so compiling it as C++ keeps all crypto_kem_* / randombytes symbols mangled
# consistently across translation units). -fcommon avoids multiple-definition
# errors from legacy tentative globals. -fpermissive downgrades the C-style
# implicit void*->T* conversions in the (C) cli.c to warnings so it compiles as
# C++; upstream sources are never edited.
g++ -O2 -fcommon -fpermissive -o "$SCRIPT_DIR/cli" \
    -I src -I src/ffi -I lib/hash -I lib/rng \
    cli.c \
    src/ffi/ffi_field.cpp src/ffi/ffi_elt.cpp src/ffi/ffi_vec.cpp \
    src/parsing.cpp src/qcrs_recoverer.cpp src/kem.cpp \
    lib/hash/hash.c lib/rng/rng.c \
    -lntl -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
