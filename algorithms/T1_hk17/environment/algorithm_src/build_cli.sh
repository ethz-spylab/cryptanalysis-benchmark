#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract HK17 sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/HK17.zip
unzip -o HK17.zip

# Use the 16-bit profile (HK17-O-128): mod=65521, degree=32.
SRC_DIR="HK17/Reference_Implementation/implementation-16bit"

# Copy all source and header files from the chosen parameter set
cp "$SRC_DIR"/*.c .
cp "$SRC_DIR"/*.h .

# Remove the KAT generation file (has its own main); program.c / octonionTest.c
# / IntermediateKAT.c are benchmark / self-test mains and are not part of the
# KEM API, so we don't compile them.
rm -f PQCgenKAT_kem.c

# Install necessary dependencies (OpenSSL for rng.c AES-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI. The KEM API lives in octonions.c lib.c rng.c HK17.c
# HK17_api.c (see the upstream makefile's SRC list).
#
# Build under strict `-std=c99` (matching the upstream makefile's
# `-ansi -std=c99 -pedantic`). The upstream lib.c/lib.h define a helper named
# `random(unsigned long)` that clashes with POSIX `random(void)` from glibc's
# <stdlib.h> under the default GNU dialect; strict c99 does NOT expose the POSIX
# prototype, so the collision disappears. argp (used by cli.c) still compiles
# and links fine under -std=c99 with the buildpack-deps toolchain. No upstream
# file is edited.
gcc -O2 -fcommon -std=c99 -o cli \
    cli.c octonions.c lib.c rng.c HK17.c HK17_api.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
