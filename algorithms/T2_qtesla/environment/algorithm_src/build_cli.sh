#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract qTESLA sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-2/submissions/qTESLA-Round2.zip
unzip -o qTESLA-Round2.zip

# Smallest parameter set: qTesla-I (heuristic security category I).
SRC="NIST_submission_round2_Mar2019/Reference_implementation/qTesla_I"

# Copy all .c/.h from the parameter set. The reference sources include the SHA-3
# and RNG helpers via subdir paths ("sha3/fips202.h", "random/random.h"), so the
# sha3/ and random/ subdirectories must be preserved alongside the top-level files.
cp "$SRC"/*.c "$SRC"/*.h .
mkdir -p sha3 random
cp "$SRC"/sha3/*.c "$SRC"/sha3/*.h sha3/
cp "$SRC"/random/*.c "$SRC"/random/*.h random/

# Remove KAT harness mains (the parameter set itself ships no main; harness
# mains live under tests/, which we never copy). Nothing to delete here, but
# guard against stray copies in case the layout changes upstream.
rm -f PQCgenKAT_sign.c PQCtestKAT_sign.c test_qtesla.c

# Install build dependencies (OpenSSL for any libcrypto symbols pulled in).
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
#   -D _AMD64_ -D __LINUX__ : architecture/platform selectors from config.h
#   -D _qTESLA_I_           : parameter-set selector used by consts.c/poly.c
#   -fcommon                : tolerate the reference impl's tentative globals
gcc -O3 -std=gnu11 -fcommon \
    -D _AMD64_ -D __LINUX__ -D _qTESLA_I_ \
    -o cli \
    cli.c sign.c pack.c sample.c gauss.c poly.c consts.c \
    sha3/fips202.c random/random.c \
    -I. -lm -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
