#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download upstream Three Bears round-2 submission.
ARCHIVE_URL="https://csrc.nist.rip/CSRC/media/Projects/post-quantum-cryptography/documents/round-2/submissions/ThreeBears-Round2.zip"
ARCHIVE_NAME="ThreeBears-Round2.zip"
# wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
unzip -o "$ARCHIVE_NAME"

apt-get update
apt-get install -y libssl-dev

# BabyBear is the smallest non-ephemeral parameter set.
SRC_DIR="$SCRIPT_DIR/ThreeBears/Reference_Implementation/crypto_kem/BabyBear"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Three Bears ships its own shake.c; the upstream Makefile links -lkeccak but
# nothing in the round-2 sources actually references libkeccak, so we drop it.
gcc -O3 -std=c11 -I. -INIST \
    cli.c \
    kem.c melas_fec.c ring.c shake.c threebears.c \
    NIST/rng.c \
    -lcrypto \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
