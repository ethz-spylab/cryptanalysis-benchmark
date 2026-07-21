#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download upstream Picnic v6.0 release.
ARCHIVE_URL="https://github.com/microsoft/Picnic/archive/refs/tags/v6.0.tar.gz"
ARCHIVE_NAME="picnic-v6.0.tar.gz"
# wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
tar xzf "$ARCHIVE_NAME"

apt-get update
apt-get install -y libssl-dev

SRC_DIR="$SCRIPT_DIR/Picnic-6.0"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Build the bundled XKCP sha3/libshake.a first (Picnic's Makefile delegates to
# sha3/ via a sub-make). Drop -Werror from the sha3 build to tolerate
# benign warnings emitted by newer gccs on that vendored code.
make -C sha3 CFLAGS="-O3 -fPIC"

# Compile the Picnic library sources and cli.c directly into the cli binary,
# linking the previously built libshake.a.
gcc -O3 -std=gnu99 \
    -D__LINUX__ -D__X64__ \
    -I. -I./sha3 \
    cli.c \
    picnic.c picnic_impl.c picnic3_impl.c lowmc_constants.c \
    hash.c picnic_types.c tree.c \
    sha3/libshake.a \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
