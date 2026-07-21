#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Yarara-Coral sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/yarara-coral.zip
unzip -o yarara-coral.zip

# Copy source files from the AEAD reference implementation (yarara128v1 variant).
# This submission bundles the Yarara AEAD cipher and the Coral hash; we build the
# AEAD (Yarara-128, the only AEAD parameter set).
cp yarara-coral/Implementations/crypto_aead/yarara128v1/ref/encrypt.c algorithm_encrypt.c
cp yarara-coral/Implementations/crypto_aead/yarara128v1/ref/api.h .

# The reference encrypt.c includes "crypto_aead.h" but the upstream zip does not
# ship that header (it only provides the function prototypes implicitly). Supply
# the standard NIST LWC AEAD prototype header so the build is self-contained.
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
    cli.c algorithm_encrypt.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
