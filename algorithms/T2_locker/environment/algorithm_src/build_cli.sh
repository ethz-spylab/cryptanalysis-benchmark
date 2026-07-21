#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract LOCKER sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/LOCKER.zip
unzip -o LOCKER.zip

# Chosen variant: LOCKER-I (smallest / 128-bit parameter set)
SRC="Reference_Implementation/LOCKER-I"

# Install build dependencies:
#   - libntl-dev / libgmp-dev : rank-metric finite-field arithmetic (NTL over GMP)
#   - libssl-dev              : OpenSSL SHA-512 (hash.c) + AES-CTR DRBG (rng.c)
apt-get update
apt-get install -y libntl-dev libgmp-dev libssl-dev

# Include paths mirror the upstream Makefile so basename includes
# ("ffi_field.h", "rng.h", ...) and the parent-relative "../parameters.h"
# used inside src/ffi/ both resolve. No upstream source is edited.
INCLUDES="-I. -I$SRC/src -I$SRC/src/ffi -I$SRC/lib/hash -I$SRC/lib/rng"

# The upstream project is C++ (g++ in its Makefile). cli.c, however, is plain C
# (it relies on C semantics like implicit void* casts in argp), so:
#   - cli.c is compiled with gcc (C), calling the locker_crypto_kem_* C-linkage
#     wrappers defined in kem_c_api.cpp;
#   - the upstream C++ sources + kem_c_api.cpp bridge are compiled with g++;
#   - everything is linked with g++.
gcc -O2 -fcommon -c cli.c $INCLUDES -o cli.o

g++ -O2 -fcommon -c kem_c_api.cpp $INCLUDES -o kem_c_api.o
g++ -O2 -fcommon -c "$SRC"/src/kem.cpp $INCLUDES -o kem.o
g++ -O2 -fcommon -c "$SRC"/src/parsing.cpp $INCLUDES -o parsing.o
g++ -O2 -fcommon -c "$SRC"/src/decoder.cpp $INCLUDES -o decoder.o
g++ -O2 -fcommon -c "$SRC"/src/ffi/ffi_field.cpp $INCLUDES -o ffi_field.o
g++ -O2 -fcommon -c "$SRC"/src/ffi/ffi_elt.cpp $INCLUDES -o ffi_elt.o
g++ -O2 -fcommon -c "$SRC"/src/ffi/ffi_vec.cpp $INCLUDES -o ffi_vec.o
g++ -O2 -fcommon -c "$SRC"/lib/hash/hash.c $INCLUDES -o hash.o
g++ -O2 -fcommon -c "$SRC"/lib/rng/rng.c $INCLUDES -o rng.o

g++ -O2 -o cli \
    cli.o kem_c_api.o kem.o parsing.o decoder.o \
    ffi_field.o ffi_elt.o ffi_vec.o hash.o rng.o \
    -lntl -lgmp -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
