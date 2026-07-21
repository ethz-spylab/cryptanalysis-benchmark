#!/bin/bash
set -e

# Get the directory where this script is located (== /crypto_oracle at runtime)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract the AIMer v2.1 (AIM2) reference implementation.
# wget https://www.kpqc.or.kr/images/zip/AIMer.zip
# The archive expands to AIMer-package/Reference_Implementation/...
# -o makes re-runs idempotent (Docker layer cache / --download-sources).
unzip -o -q AIMer-package.zip

SRC="AIMer-package/Reference_Implementation"
if [ ! -f "$SRC/aim2.c" ]; then
    echo "Error: expected '$SRC/aim2.c' not found after unzip" >&2
    exit 1
fi

# Compile the CLI against only the AIM2 one-way function (not the signature
# machinery sign.c/tree.c, nor the keygen DRBG common/rng.c / common/aes.c).
# aim2() needs: aim2.c, hash.c, the field arithmetic (field128.c for the
# 128-bit set), and the SHAKE implementation common/fips202.c (used by the
# IV-driven linear-layer generation).
#
# -DPARAMS=128s selects the 128-bit parameter set: params.h does
# `#include xstr(params/params-aimer-PARAMS.h)`, so -I"$SRC" resolves both
# `params/params-aimer-128s.h` and the local headers. The s/f suffix only
# changes the signature MPC parameters (T/N); the AIM2 primitive is identical,
# so 128s vs 128f is irrelevant for the `hash` oracle.
# -I. resolves the local cli_stdin.h. AIMer v2.1 removed the OpenSSL
# dependency, so no -lcrypto is needed.
gcc -I. -I"$SRC" -O3 -march=native -DPARAMS=128s \
    -Wno-sign-compare -Wno-unused-but-set-variable \
    -Wno-unused-parameter -Wno-unused-result \
    cli.c \
    "$SRC/aim2.c" \
    "$SRC/hash.c" \
    "$SRC/field128.c" \
    "$SRC/common/fips202.c" \
    -o cli

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
