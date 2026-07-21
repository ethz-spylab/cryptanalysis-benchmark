#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract DAGS sources (NIST PQC Round 1 submission).
unzip -o DAGS.zip

# Variant: DAGS_1 is not shipped in the official Round-1 archive (only
# dags3 / dags5 reference implementations exist). dags3 is the smallest
# *buildable* parameter set (NIST level 3, "DAG 96" parameters), so we use it.
SRC_DIR="DAGS/Reference_Implementation/kem/dags3"

# Copy all reference source + header files (every module DAGS needs).
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Copy the bundled KangarooTwelve / Keccak headers and prebuilt static library.
# The source includes <keccak/KangarooTwelve.h>, and that header reaches into
# ../keccak/* relative to itself, so the whole keccak/ dir must stay intact.
cp -r "$SRC_DIR"/keccak .
cp "$SRC_DIR"/libkeccak.a .

# Remove the KAT generation file (it has its own main()).
rm -f PQCgenKAT_kem.c

# --- Work around upstream defects in the *copied* sources (the pristine
# --- archive in DAGS.zip is never modified):
#
# 0. The reference sources are DOS/CRLF-encoded. Normalise every copied .c/.h
#    to LF so the line-oriented fixes below match reliably and so no stray
#    carriage returns leak into tokens.
sed -i 's/\r$//' *.c *.h
#
# 1. api.h ends with a stray "%" byte after the final #endif, which is not
#    valid C and aborts the preprocessor (and cascades into spurious errors in
#    every system header that follows). Strip the lone "%" line.
sed -i '/^%$/d' api.h
#
# 2. param.h opens with `#ifndef GF_H / #define GF_H / #endif`, hijacking the
#    include guard that gf.h uses. When a translation unit pulls in param.h
#    (via decoding.h) before gf.h, gf.h's body — including `typedef uint16_t
#    gf;` — is skipped, so `gf` is undefined and compilation cascades into
#    bogus errors. Strip those three bogus guard lines (they are the first
#    three lines of param.h); the parameter #defines below are emitted
#    unconditionally and are unaffected.
if [ "$(sed -n '1,3p' param.h)" = "$(printf '#ifndef GF_H\n#define GF_H\n#endif')" ]; then
  sed -i '1,3d' param.h
fi

# Install dependencies: rng.c uses OpenSSL's AES for the NIST CTR-DRBG.
apt-get update
apt-get install -y libssl-dev unzip

# Compile the CLI. -I. resolves <keccak/KangarooTwelve.h>; the bundled
# libkeccak.a provides KangarooTwelve; -lcrypto covers rng.c. -fcommon keeps
# the legacy (pre-GCC-10) tentative-definition behaviour the sources assume.
gcc -O2 -fcommon -o cli \
    cli.c \
    decapsulation.c decoding.c encapsulation.c fichier.c gf.c kem.c \
    key_gen.c matrix.c poly.c rng.c util.c \
    -I. -L. -lkeccak -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
