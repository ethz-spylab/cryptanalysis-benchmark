#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract TGIF sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/tgif.zip
unzip -o tgif.zip

# Copy source files from the reference implementation (TGIF-N1 primary variant)
cp tgif/Implementations/crypto_aead/tgifn1128v1/ref/encrypt.c algorithm_encrypt.c
cp tgif/Implementations/crypto_aead/tgifn1128v1/ref/TGIF_BC.c .
cp tgif/Implementations/crypto_aead/tgifn1128v1/ref/bc.h .
cp tgif/Implementations/crypto_aead/tgifn1128v1/ref/variant.h .
cp tgif/Implementations/crypto_aead/tgifn1128v1/ref/api.h .

# The TGIF reference does not ship a crypto_aead.h prototype header, but
# encrypt.c includes one. Provide the standard NIST AEAD prototype header so
# cli.c (the shared AEAD template) and encrypt.c agree on the API.
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
    cli.c algorithm_encrypt.c TGIF_BC.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
