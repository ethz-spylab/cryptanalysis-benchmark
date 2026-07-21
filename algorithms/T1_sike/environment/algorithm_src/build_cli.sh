#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SIKE sources
# wget https://csrc.nist.gov/csrc/media/Projects/post-quantum-cryptography/documents/round-4/submissions/SIKE-Round4.zip
unzip SIKE-Round4.zip

# Copy needed source and header files from the reference implementation
# Library sources (matching CMakeLists.txt LIBRARY_FILES)
cp Reference_Implementation/src/fp.c \
   Reference_Implementation/src/sike_params.c \
   Reference_Implementation/src/fp2.c \
   Reference_Implementation/src/sidh.c \
   Reference_Implementation/src/sike.c \
   Reference_Implementation/src/encoding.c \
   Reference_Implementation/src/isogeny.c \
   Reference_Implementation/src/api_generic.c \
   Reference_Implementation/src/montgomery.c \
   .

# Headers
cp Reference_Implementation/include/*.h .

# Symmetric primitives (SHAKE/SHA3, all RNG headers, and AES support)
# fp.c and sike.c include <rng.h>, sidh.c includes <random.h>
# We use random.c (/dev/urandom) as the randombytes() implementation
# and include aes_c.c for the AES dependency in rng.h
cp Reference_Implementation/symmetric/fips202.c \
   Reference_Implementation/symmetric/fips202.h \
   Reference_Implementation/symmetric/rng.h \
   Reference_Implementation/symmetric/random.h \
   Reference_Implementation/symmetric/random.c \
   Reference_Implementation/symmetric/aes.h \
   Reference_Implementation/symmetric/aes_c.c \
   Reference_Implementation/symmetric/aes_local.h \
   .

# Clean up downloaded archive and extracted directories
# rm -rf SIKE-Round4.zip Additional_Implementations KAT License.txt \
#        Optimized_Implementation README Reference_Implementation \
#        Supporting_Documentation

# Install necessary dependencies
# apt-get update
# apt-get install -y libgmp-dev

# Compile the CLI
gcc -O3 -std=c99 -o cli \
    cli.c \
    fp.c sike_params.c fp2.c sidh.c sike.c encoding.c \
    isogeny.c api_generic.c montgomery.c fips202.c random.c aes_c.c \
    -I. -lgmp

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
