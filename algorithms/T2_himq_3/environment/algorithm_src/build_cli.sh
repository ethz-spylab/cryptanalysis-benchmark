#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract HiMQ-3 sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/HiMQ_3.zip
unzip -o HiMQ_3.zip

# Copy all source and header files from the smallest parameter set
# (Reference_Implementation/HiMQ-3). The HiMQ-3 and HiMQ-3F sets share the
# same key/signature sizes; HiMQ-3 is the base (non-"F") set.
cp "HiMQ-3/Reference_Implementation/HiMQ-3/"*.c .
cp "HiMQ-3/Reference_Implementation/HiMQ-3/"*.h .

# Remove the reference test harness (has its own main)
rm -f test.c

# Bug fix (build-time patch of the extracted copy, not the vendored tree):
# In sign_layer12() the VLA `temp_ans[numfun]` is sized by `numfun` (15) but is
# indexed by the *absolute* signature index, which for index==2 runs up to
# start+numfun-1 = 29 (start=O1=15). This overruns the buffer and triggers
# "*** stack smashing detected ***" during crypto_sign. The array is logically
# the per-message-coordinate workspace, so sizing it to M (=44, the message
# field count, >= the highest index used in both layers) is the correct fix.
sed -i 's/unsigned char temp_ans\[numfun\];/unsigned char temp_ans[M];/' sign.c

# Install necessary dependencies (OpenSSL for the SHA-512 message hash in cli.c)
apt-get update
apt-get install -y libssl-dev

# Compile the CLI.
# -fcommon: the reference sources rely on tentative-definition merging.
gcc -O2 -fcommon -o cli \
    cli.c gf256.c mq.c sign.c \
    -I. -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
