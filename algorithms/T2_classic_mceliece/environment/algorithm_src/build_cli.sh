#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download upstream Classic McEliece round-4 package.
ARCHIVE_URL="https://classic.mceliece.org/nist/mceliece-20221023.tar.gz"
ARCHIVE_NAME="mceliece-20221023.tar.gz"
# wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"
tar xzf "$ARCHIVE_NAME"

# Upstream includes <libkeccak.a.headers/SimpleFIPS202.h> from XKCP, which is
# not packaged in Ubuntu apt repos. Build libkeccak.a from XKCP sources and
# install headers+lib into /usr/local.
apt-get update
apt-get install -y libssl-dev xsltproc git

if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  # Upstream renamed libkeccak.a -> libXKCP.a; install under both the new
  # and legacy name + include path so existing -lkeccak / -I.../libkeccak.a.headers
  # references keep working without touching every caller.
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
fi

SRC_DIR="$SCRIPT_DIR/mceliece-20221023/Reference_Implementation/kem/mceliece348864"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Compile flags mirror the upstream ./build script, minus -march=native for
# portability. CRYPTO_NAMESPACE(x)=x collapses the namespace macro to identity.
gcc -O3 -std=c99 \
    -I. -Isubroutines -Inist -I/usr/local/include \
    "-DCRYPTO_NAMESPACE(x)=x" "-D_CRYPTO_NAMESPACE(x)=_##x" \
    -include crypto_kem.h \
    cli.c nist/rng.c \
    benes.c bm.c controlbits.c decrypt.c encrypt.c gf.c operations.c \
    pk_gen.c root.c sk_gen.c synd.c transpose.c util.c \
    -L/usr/local/lib -lkeccak -lcrypto -ldl \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
