#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Giophantus sources
unzip -o Giophantus.zip

# Use the Reference_Implementation, IEC602 parameter set:
#   N=1201, MLEN=16 -> 128-bit security == NIST level 1.
SRC="Giophantus_R/Reference_Implementation/encrypt/IEC602"
cp "$SRC"/*.c .
cp "$SRC"/*.h .

# Remove sources that carry their own main() (KAT harness, benchmark, sample,
# intermediate-value dumps) and the optimized poly variant (Makefile uses
# poly.c, not polyopt.c).
rm -f PQCgenKAT_encrypt.c benchmark.c sample.c intermediate-main.c \
      intermediate-iec.c polyopt.c

# Install necessary dependencies. The bundled rng.c uses its own aes256.c
# (OpenSSL is disabled in the source), so libssl is not strictly required, but
# install it for parity with the other PQC tasks in case the build env needs it.
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. Library sources per the upstream Makefile OBJS list:
#   iec.c poly.c genrand.c rng.c aes256.c seedexpand.c sha3.c
# -fcommon tolerates the upstream's tentative global definitions.
gcc -O2 -fcommon -o cli \
    cli.c iec.c poly.c genrand.c rng.c aes256.c seedexpand.c sha3.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
