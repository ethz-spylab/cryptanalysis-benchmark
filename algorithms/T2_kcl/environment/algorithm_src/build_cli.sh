#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract the KCL (OKCN/AKCN/CNKE) submission archive
unzip -o OKCN_AKCN_CNKE.zip

# Chosen variant: OKCN-MLWE (smallest parameter set; module-LWE, N=256, ELL=3).
SRC="OKCN_AKCN_CNKE/Reference_Implementation/kem/OKCN-MLWE/ref"

# Copy all source and header files for the chosen parameter set
cp "$SRC"/*.c .
cp "$SRC"/*.h .

# Remove files that ship their own main() (KAT / speed / intermediate harnesses)
rm -f okcn-mlwe.c okcn-mlwe-KATgen.c okcn-mlwe-intermediate-gen.c \
      PQCgenKAT_kem.c speed.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. rng.c needs -lcrypto; polynomial/io use libm (-lm).
gcc -O2 -fcommon -o cli \
    cli.c kem.c polynomial.c reduce.c io.c okcn.c vector.c rng.c \
    -I. -lssl -lcrypto -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
