#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Clone the upstream LAC repository at a pinned commit for reproducibility.
LAC_COMMIT="c0453fd1b5c803dd9b4fc5142be42c242da78034"
if [ ! -d LAC ]; then
  apt-get update
  apt-get install -y git libssl-dev zlib1g-dev
  # git clone https://github.com/zhenfeizhang/LAC.git
  tar xzf vendored-LAC.tar.gz
  # (cd LAC && git checkout "$LAC_COMMIT")
fi

# Apply local patches (see CHANGES.md for the rationale behind each).
# Upstream LAC source ships with CRLF line endings, while our patches are LF.
# Strip CRs from the files the patches target so `patch` matches cleanly.
find LAC/LAC-v3a/ref -type f -name '*.[ch]' -exec sed -i 's/\r$//' {} +

for p in patches/*.patch; do
  patch -p1 -d LAC < "$p"
done

# LAC-v3a is the DFR-lowered update per sources.txt; `ref/` is the portable
# C reference. LAC128 is the Category-1 parameter set, selected via the patch.
SRC_DIR="$SCRIPT_DIR/LAC/LAC-v3a/ref"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Library sources only (skip main.c and the test_*.c harnesses, which define
# their own main()).
gcc -O3 -Wall -I. \
    cli.c \
    ake.c ke.c kem.c encrypt.c ecc.c bch.c bin-lwe.c rand.c rng.c \
    -lcrypto -lz \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
