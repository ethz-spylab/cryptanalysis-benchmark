#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Bleep64 sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/bleep64.zip
unzip -o bleep64.zip

# Copy source files from the reference implementation (bleep64 ref variant)
cp bleep64/Implementations/crypto_aead/bleep64/ref/encrypt.c algorithm_encrypt.c
cp bleep64/Implementations/crypto_aead/bleep64/ref/api.h .

# The Bleep64 reference ships only api.h + encrypt.c (no crypto_aead.h).
# Provide the standard NIST AEAD API prototype header the CLI includes.
cat > crypto_aead.h <<'EOF'

int crypto_aead_encrypt(
	unsigned char *c, unsigned long long *clen,
	const unsigned char *m, unsigned long long mlen,
	const unsigned char *ad, unsigned long long adlen,
	const unsigned char *nsec,
	const unsigned char *npub,
	const unsigned char *k
);

int crypto_aead_decrypt(
	unsigned char *m, unsigned long long *mlen,
	unsigned char *nsec,
	const unsigned char *c, unsigned long long clen,
	const unsigned char *ad, unsigned long long adlen,
	const unsigned char *npub,
	const unsigned char *k
);
EOF

# Compile the CLI.
# The reference uses GCC nested functions and old-style (K&R) declarations.
# Bleep64() is declared `inline`; under C99 inline semantics that emits no
# external symbol, so use -fgnu89-inline so crypto_aead_encrypt/decrypt can
# link against it. -fno-strict-aliasing because the impl type-puns byte/word
# pointers heavily.
gcc -O2 -std=gnu99 -fgnu89-inline -fno-strict-aliasing -o cli \
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
