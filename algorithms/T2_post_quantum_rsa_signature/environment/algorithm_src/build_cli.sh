#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Upstream Post-quantum RSA signature package (NIST PQC round 1).
ARCHIVE_NAME="PostQuantum_RSA_Sign.zip"
rm -rf PostQuantum_RSA_Sign
unzip -q -o "$ARCHIVE_NAME"

# Build dependencies:
#  - GMP   : the scheme is huge-modulus RSA implemented with mpz_t big integers.
#  - OpenSSL: the NIST DRBG (nist/rng.c) uses AES via libcrypto.
#  - XKCP  : sign.c / open.c include <libkeccak.a.headers/KeccakSpongeWidth1600.h>
#            and call KeccakWidth1600_Sponge, which is not packaged in apt.
apt-get update
apt-get install -y libgmp-dev libssl-dev xsltproc git

if [ ! -f /usr/local/lib/libkeccak.a ]; then
  # git clone --depth 1 --recurse-submodules https://github.com/XKCP/XKCP.git
  tar xzf vendored-XKCP.tar.gz
  (cd XKCP && make generic64/libXKCP.a)
  # Upstream sources include <libkeccak.a.headers/...> and link -lkeccak; XKCP
  # renamed these to libXKCP. Install under the legacy name + include path so the
  # unmodified upstream sources keep building.
  mkdir -p /usr/local/include/libkeccak.a.headers
  cp -r XKCP/bin/generic64/libXKCP.a.headers/* /usr/local/include/libkeccak.a.headers/
  cp XKCP/bin/generic64/libXKCP.a /usr/local/lib/libkeccak.a
  # The upstream pqrsa sources include the legacy SUPERCOP header name
  # <libkeccak.a.headers/KeccakSpongeWidth1600.h>; modern XKCP exposes the same
  # KeccakWidth1600_Sponge() function through KeccakSponge.h. Provide a shim
  # alias header (we never edit the upstream sources themselves).
  echo '#include "KeccakSponge.h"' \
    > /usr/local/include/libkeccak.a.headers/KeccakSpongeWidth1600.h
fi

# Smallest / quickest signature parameter set (pqrsa15): 32 KiB public key,
# 96 KiB secret key, 32 KiB signature. The larger sets (pqrsa20/25/30) jump to
# 1 MiB .. 1 GiB keys and are infeasible to run in a task container.
SRC_DIR="$SCRIPT_DIR/PostQuantum_RSA_Sign/Reference_Implementation/sign/pqrsa15"
cp cli.c cli_stdin.h "$SRC_DIR/"
cd "$SRC_DIR"

# Mirror the upstream ./build flags, minus -march/-mtune=native for portability
# and WITHOUT -DKAT. -include crypto_sign.h maps crypto_sign_* onto
# the pqrsa15 namespace. -fcommon tolerates the upstream's tentative
# definitions.
gcc -O3 -std=c99 -fcommon \
    -I. -Inist -I/usr/local/include \
    -include crypto_sign.h \
    cli.c nist/rng.c \
    open.c sign.c gmp_export.c gmp_import.c \
    -L/usr/local/lib -lkeccak -lgmp -lcrypto -ldl \
    -o "$SCRIPT_DIR/cli"

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
