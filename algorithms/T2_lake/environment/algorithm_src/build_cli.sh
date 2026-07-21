#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract LAKE sources (standalone Round-1 submission, later
# merged into ROLLO). See download_source.sh for the URL.
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/LAKE.zip
unzip -o LAKE.zip

# Chosen variant: LAKE-I (NIST level 1, 128-bit security — the smallest set).
SRC="Reference_Implementation/LAKE-I"

# Drop cli.c / cli_stdin.h into the variant's src/ dir so that the upstream's
# relative #include directives (e.g. ffi.h's #include "../parameters.h", which
# expects src/ffi/ -> src/) keep resolving. We compile in place and never edit
# any upstream file. Include paths cover src/, src/ffi/, lib/hash/, lib/rng/.
cp cli.c cli_stdin.h "$SRC/src/"

# Remove the KAT / standalone mains (they each define their own main()).
rm -f "$SRC"/src/main_kat.c "$SRC"/src/main_lake.cpp

# Rank-metric, NTL-based KEM: needs NTL + GMP, plus OpenSSL for the NIST
# AES-CTR DRBG (rng.c) and the SHA512 hash wrapper (hash.c).
apt-get update
apt-get install -y libgmp-dev libntl-dev libssl-dev

# Everything is compiled with g++: the upstream KEM API (crypto_kem_*) is
# defined in C++ translation units with no extern "C" wrapper, so cli.c must
# also be compiled as C++ to get matching (mangled) linkage. g++ compiles the
# .c files (rng.c, hash.c) as C++ too, keeping all linkage uniform.
# -fpermissive: cli.c is a C source compiled here as C++ (for linkage with the
# C++ KEM API); g++ would otherwise reject C-legal implicit void* conversions.
g++ -O2 -fcommon -fpermissive -std=c++11 -w -o cli \
    -I"$SRC/src" -I"$SRC/src/ffi" -I"$SRC/lib/hash" -I"$SRC/lib/rng" \
    "$SRC/src/cli.c" \
    "$SRC/src/kem.cpp" "$SRC/src/decoder.cpp" "$SRC/src/parsing.cpp" \
    "$SRC/src/ffi/ffi_field.cpp" "$SRC/src/ffi/ffi_elt.cpp" "$SRC/src/ffi/ffi_vec.cpp" \
    "$SRC/lib/rng/rng.c" "$SRC/lib/hash/hash.c" \
    -lntl -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
