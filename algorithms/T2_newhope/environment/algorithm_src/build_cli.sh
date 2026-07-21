#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Clone the upstream NewHope repository at a pinned commit for reproducibility.
NEWHOPE_COMMIT="276551a21be7c3c38f80d619ddea2feb2e1572e6"
if [ ! -d newhope ]; then
  apt-get update
  apt-get install -y git libssl-dev
  # git clone https://github.com/newhopecrypto/newhope.git
  tar xzf vendored-newhope.tar.gz
  # (cd newhope && git checkout "$NEWHOPE_COMMIT")
fi

SRC_DIR="$SCRIPT_DIR/newhope/ref"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# The upstream Makefile symlinks ccakem.h to api.h before compiling; do the
# same so cli.c's `#include "api.h"` resolves to the CCA-KEM API.
ln -sf ccakem.h api.h

# NewHope-512 selected via -DNEWHOPE_N=512 (params.h uses an #ifndef guard,
# so the compile-time flag cleanly overrides the 1024 default).
gcc -O3 -std=c99 -I. \
    -DNEWHOPE_N=512 \
    cli.c \
    poly.c reduce.c fips202.c verify.c cpapke.c ntt.c precomp.c ccakem.c \
    rng.c \
    -lcrypto \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
