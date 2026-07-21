#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract REMUS sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/remus.zip
unzip -o remus.zip

# Copy source files from the reference implementation (REMUS-N1 variant, remusn1v1)
REF=remus/Implementations/crypto_aead/remusn1v1/ref
cp "$REF/encrypt.c" algorithm_encrypt.c
cp "$REF/skinny_reference.c" .
cp "$REF/bc.h" .
cp "$REF/api.h" .
cp "$REF/variant.h" .

# REMUS does not ship a crypto_aead.h (encrypt.c #includes it); provide the
# standard NIST AEAD prototypes so encrypt.c and cli.c compile against them.
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

# Compile the CLI
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c skinny_reference.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
