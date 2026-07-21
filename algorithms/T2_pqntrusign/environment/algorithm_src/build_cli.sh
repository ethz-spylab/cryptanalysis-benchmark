#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract pqNTRUsign sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/pqNTRUsign.zip
unzip -o pqNTRUsign.zip

# Install necessary dependencies (OpenSSL for rng.c AES-256-CTR DRBG)
apt-get update
apt-get install -y libssl-dev

# Chosen parameter set: Gaussian-1024 (smallest available; the only other set,
# Uniform-1024, has identical key/signature sizes).
PARAM=Gaussian-1024
REF="pqNTRUsign/Reference_Implementation"

# Preserve the upstream directory layout so the `../common/...` relative includes
# inside sign.c resolve unchanged (we never edit upstream sources):
#   ./common/   <- shared sources + headers
#   ./param/    <- the chosen parameter set's sign.c + api.h (sibling of common/)
rm -rf common param
cp -r "$REF/common" common
mkdir -p param
cp "$REF/$PARAM/sign.c" "$REF/$PARAM/api.h" param/

# Fix an upstream undefined-behavior bug in extendedEuclid (common/NTT.c):
# the recursive helper returns a pointer to its local `int64_t array[3]`, so
# InvMod() dereferences a dangling stack pointer once the deepest frame is gone.
# This "works" only at -O0 and segfaults at -O2. Promote the buffer to `static`
# so its storage survives the return; the CLI is single-threaded and each
# InvMod() fully consumes the result before the next call, so the algorithm's
# behaviour is unchanged. (We patch the build copy here, never the vendored
# archive — same approach RaCoSS uses for its verified upstream fixes.)
sed -i 's/^\( *\)int64_t array\[3\];/\1static int64_t array[3];/' common/NTT.c

# Fix the upstream message-length truncation typo in challenge() (see
# fix_challenge_msglen.patch for the full rationale): sign()/verify() hardcode a
# 32-byte message length when calling challenge() instead of passing the real
# msg_len, so only the first 32 bytes of a message are authenticated. The spec
# hashes the full message, so we restore msg_len at both call sites. Patched on
# the build copy (common/), never the vendored archive -- same as the NTT.c fix.
patch -p0 < fix_challenge_msglen.patch

# Compile the CLI.
#   - cli.c needs api.h (param set), rng.h (common), cli_stdin.h (cwd)
#   - param/sign.c includes "../common/..." -> resolves because common/ is its
#     sibling directory
#   - -fcommon tolerates legacy tentative-definition globals
COMMON_SRCS=$(ls common/*.c)
gcc -O2 -fcommon -o cli \
    cli.c param/sign.c $COMMON_SRCS \
    -Iparam -Icommon -I. \
    -lm -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
