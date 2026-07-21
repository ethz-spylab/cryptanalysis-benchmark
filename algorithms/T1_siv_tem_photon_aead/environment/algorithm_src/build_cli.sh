#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SIV-TEM-PHOTON sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/siv-tem-photon.zip
unzip -o siv-tem-photon.zip

# Copy source files from the reference implementation (sivtemphotonaeadv1 variant)
REF=siv-tem-photon/Implementations/crypto_aead/sivtemphotonaeadv1/ref
cp "$REF/encrypt.c" algorithm_encrypt.c
cp "$REF/photon.c" .
cp "$REF/photon.h" .
cp "$REF/siv.h" .
cp "$REF/api.h" .

# The upstream submission omits the standard NIST AEAD API header
# (crypto_aead.h) that encrypt.c includes; it is expected one directory up in
# the NIST layout. Recreate it verbatim (declarations only) without touching the
# upstream source. This matches the byte-for-byte standard NIST AEAD prototypes.
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

# Compile the CLI (photon.c uses math.h -> -lm)
gcc -O2 -std=c99 -o cli \
    cli.c algorithm_encrypt.c photon.c \
    -I. -lm

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
