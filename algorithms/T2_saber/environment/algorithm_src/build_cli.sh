#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Clone the upstream SABER repository at a pinned commit for reproducibility.
SABER_COMMIT="f7f39e4db2f3e22a21e1dd635e0601caae2b4510"
if [ ! -d SABER ]; then
  apt-get update
  apt-get install -y git libssl-dev
  # git clone https://github.com/KULeuven-COSIC/SABER.git
  tar xzf vendored-SABER.tar.gz
  # (cd SABER && git checkout "$SABER_COMMIT")
fi

# Apply local patches (see CHANGES.md for the rationale behind each).
for p in patches/*.patch; do
  patch -p1 -d SABER < "$p"
done

# LightSaber is selected via the SABER_L=2 patch above.
SRC_DIR="$SCRIPT_DIR/SABER/Reference_Implementation_KEM"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

gcc -O3 -std=c99 -I. \
    cli.c \
    pack_unpack.c poly.c fips202.c verify.c cbd.c SABER_indcpa.c kem.c \
    rng.c \
    -lcrypto \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
