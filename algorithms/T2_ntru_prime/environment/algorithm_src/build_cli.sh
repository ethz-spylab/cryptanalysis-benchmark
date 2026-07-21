#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download upstream NTRU Prime round-3 package.
ARCHIVE_URL="https://ntruprime.cr.yp.to/nist/ntruprime-20201007.tar.gz"
ARCHIVE_NAME="ntruprime-20201007.tar.gz"
# wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
tar xzf "$ARCHIVE_NAME"

apt-get update
apt-get install -y libssl-dev

# sntrup653 is the smallest Streamlined NTRU Prime parameter set considered safe.
SRC_DIR="$SCRIPT_DIR/ntruprime-20201007/Reference_Implementation/kem/sntrup653"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

gcc -O3 -std=c99 \
    -I. -Isubroutines -Inist \
    "-DCRYPTO_NAMESPACE(x)=x" \
    -include crypto_kem.h \
    cli.c nist/rng.c \
    Decode.c Encode.c int32.c kem.c uint32.c \
    subroutines/crypto_hash_sha512.c subroutines/crypto_sort_uint32.c \
    subroutines/crypto_stream_aes256ctr.c \
    -lcrypto -ldl \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
