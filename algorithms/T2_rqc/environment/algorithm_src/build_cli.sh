#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract RQC sources
unzip -o RQC-Round2.zip

# Smallest parameter set: RQC-128 (RQC-I, 128-bit security level).
SRC=RQC/Reference_Implementation/rqc128

# Flatten all source/header files into the build directory. The upstream
# sources spread across src/, src/ffi/, lib/hash/, lib/rng/ but every local
# #include uses a bare filename, so flattening + "-I." resolves everything.
cp "$SRC"/src/*.cpp "$SRC"/src/*.h .
cp "$SRC"/src/ffi/*.cpp "$SRC"/src/ffi/*.h .
cp "$SRC"/lib/hash/hash.c "$SRC"/lib/hash/hash.h .
cp "$SRC"/lib/rng/rng.c "$SRC"/lib/rng/rng.h .

# Remove the upstream entry points (each provides its own main()).
rm -f main_rqc.cpp main_kat.c

# Install build dependencies:
#   - NTL + GMP: the finite-field / rank-metric arithmetic library
#   - OpenSSL: rng.c AES-256-CTR DRBG and hash.c SHA-512 wrapper
apt-get update
apt-get install -y libgmp-dev libntl-dev libssl-dev

# Compile everything with g++ (the bulk of the upstream sources are C++ and
# the C files compile cleanly as C++). The headers carry no extern "C", so a
# single compiler keeps name mangling consistent across all translation units.
#
# cli.c is the canonical KEM CLI shared verbatim across all KEM tasks; it was
# written to be compiled as C. Building it as C++ here is required so its calls
# to crypto_kem_* / randombytes_init resolve to the C++-mangled symbols in the
# upstream objects. -fpermissive downgrades the one C-vs-C++ strictness gap
# (implicit void* -> T* conversion in cli.c) to a warning; no source is edited.
g++ -O2 -fcommon -fpermissive -o cli \
    cli.c \
    ffi_elt.cpp ffi_field.cpp ffi_vec.cpp \
    parsing.cpp q_polynomial.cpp gabidulin.cpp rqc.cpp kem.cpp \
    hash.c rng.c \
    -I. -pthread -lntl -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
