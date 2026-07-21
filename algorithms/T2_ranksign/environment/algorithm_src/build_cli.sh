#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract RankSign sources
unzip -o RankSign.zip

# Smallest / primary parameter set: RankSign-I (NIST security level 1).
REF=RankSign/Reference_Implementation/RankSign-I
TPL=RankSign/Third_Party_Library

# Flatten the scheme sources into the build directory. Upstream spreads files
# across src/, src/ffi/, and the shared third-party lib/{rng,hash,mpfq}. The
# ffi sources use "../parameters.h" / "../VS.h", so we ALSO keep an include
# path one level up by adding -I flags rather than editing upstream.
cp "$REF"/src/*.c "$REF"/src/*.h .
cp "$REF"/src/ffi/*.c "$REF"/src/ffi/*.h .

# Third-party NIST DRBG (rng.c, OpenSSL AES-256-CTR) and SHA-512 wrapper (hash.c)
cp "$TPL"/lib/rng/rng.c "$TPL"/lib/rng/rng.h .
cp "$TPL"/lib/hash/hash.c "$TPL"/lib/hash/hash.h .

# MPFQ finite-field library: RankSign-I uses the GF(2^32) field. The submission
# ships a prebuilt static archive plus the matching headers (mpfq_2_32.h pulls
# in the mpfq/ subdir of headers).
MPFQ_INC="$TPL/lib/mpfq/include"
cp "$TPL"/lib/mpfq/mpfq-1.1/src/gf2n/libmpfq_2_32.a libmpfq_2_32.a

# The ffi sources include "../parameters.h" and "../VS.h"; after flattening,
# those headers live in the build dir, so a copy under a fake parent satisfies
# the relative include without touching upstream.
mkdir -p _parent
cp parameters.h VS.h _parent/

# Remove the upstream entry points (each provides its own main()).
rm -f main_ranksign.c main_kat.c

# Install build dependencies:
#   - GMP: MPFQ multiprecision arithmetic backend
#   - OpenSSL: rng.c AES-256-CTR DRBG and hash.c SHA-512 wrapper
apt-get update
apt-get install -y libgmp-dev libssl-dev

# Compile. The ffi/*.c relative includes ("../parameters.h") are resolved via
# the -I_parent shim; the bundled MPFQ headers via -I"$MPFQ_INC"; everything
# else (flattened sources) via -I. and the bare-name includes.
# -fcommon avoids multiple-definition errors from upstream's tentative globals.
# -no-pie is required because the prebuilt MPFQ static archive (libmpfq_2_32.a)
# was assembled without PIE-compatible relocations (R_X86_64_32 in .rodata),
# which the default PIE link on modern toolchains rejects.
gcc -O2 -std=c99 -fcommon -no-pie -o cli \
    cli.c \
    ffi_field.c ffi_elt.c ffi_vecmat.c ffi_basevecmat.c \
    parsing.c ranksign.c VS.c \
    rng.c hash.c \
    -I. -I_parent -I"$MPFQ_INC" \
    libmpfq_2_32.a -lgmp -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
