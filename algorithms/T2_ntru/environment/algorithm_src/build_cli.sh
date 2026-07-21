#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download upstream NTRU round-3 package.
ARCHIVE_URL="https://csrc.nist.gov/CSRC/media/Projects/post-quantum-cryptography/documents/round-3/submissions/NTRU-Round3.zip"
ARCHIVE_NAME="NTRU-Round3.zip"
# wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
unzip -o "$ARCHIVE_NAME"

apt-get update
apt-get install -y libssl-dev

# ntruhps2048509 is the Category-1 HPS variant per sources.txt.
SRC_DIR="$SCRIPT_DIR/NIST-PQ-Submission-NTRU-20201016/Reference_Implementation/crypto_kem/ntruhps2048509"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# CRYPTO_NAMESPACE defaults to identity in params.h, so we omit the -D override
# the upstream Makefile uses (it prefixes symbols with `ntru_`).
gcc -O3 -std=c99 -I. \
    "-DCRYPTO_NAMESPACE(x)=x" \
    cli.c \
    cmov.c crypto_sort_int32.c fips202.c kem.c owcpa.c pack3.c packq.c \
    poly.c poly_lift.c poly_mod.c poly_r2_inv.c poly_rq_mul.c poly_s3_inv.c \
    rng.c sample.c sample_iid.c \
    -lcrypto \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
