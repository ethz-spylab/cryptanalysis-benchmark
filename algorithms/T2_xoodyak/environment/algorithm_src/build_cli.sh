#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Xoodyak sources
# wget https://csrc.nist.gov/CSRC/media/Projects/lightweight-cryptography/documents/finalist-round/updated-submissions/xoodyak.zip
unzip -o xoodyak.zip

# Reference AEAD variant (portable 32-bit C reference, not SIMD/asm)
REF=xoodyak/Implementations/crypto_aead/xoodyakround3/ref

# Copy source files from the reference implementation
cp "$REF/encrypt.c" algorithm_encrypt.c
cp "$REF/Xoodyak.c" .
cp "$REF/Xoodoo-reference.c" .
cp "$REF/Xoodyak.h" .
cp "$REF/Xoodoo.h" .
cp "$REF/Xoodoo-SnP.h" .
cp "$REF/Cyclist.h" .
cp "$REF/Cyclist.inc" .
cp "$REF/align.h" .
cp "$REF/brg_endian.h" .
cp "$REF/api.h" .

# The Xoodyak reference does not ship the standard NIST LWC crypto_aead.h
# header that encrypt.c / cli.c include; provide the canonical declarations.
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
    cli.c algorithm_encrypt.c Xoodyak.c Xoodoo-reference.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
