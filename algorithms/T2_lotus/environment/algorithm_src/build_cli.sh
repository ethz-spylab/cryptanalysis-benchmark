#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Fetch upstream reference implementation.
# wget https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-2/submissions-rnd2/lotus-locus.zip -O lotus-locus.zip
unzip -q lotus-locus.zip

REFDIR="lotus-locus/Implementations/crypto_aead/twegift64lotusaeadv1/ref"

# Copy all C sources and headers from the reference directory, skipping
# the stand-alone KAT-generator main (genkat_aead.c) so it does not clash
# with cli.c's main().
for f in "$REFDIR"/*.h "$REFDIR"/*.c "$REFDIR"/*.inc; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    if [ "$base" = "genkat_aead.c" ]; then
        continue
    fi
    cp "$f" .
done

# Some reference implementations do not ship a crypto_aead.h header even
# though encrypt.c implements the standard NIST LWC AEAD API. Provide a
# minimal declaration-only header when one is missing so cli.c compiles.
if [ ! -f crypto_aead.h ]; then
    cat > crypto_aead.h <<'HEOF'
#ifndef CRYPTO_AEAD_H
#define CRYPTO_AEAD_H

int crypto_aead_encrypt(unsigned char *c, unsigned long long *clen,
                        const unsigned char *m, unsigned long long mlen,
                        const unsigned char *ad, unsigned long long adlen,
                        const unsigned char *nsec,
                        const unsigned char *npub,
                        const unsigned char *k);

int crypto_aead_decrypt(unsigned char *m, unsigned long long *mlen,
                        unsigned char *nsec,
                        const unsigned char *c, unsigned long long clen,
                        const unsigned char *ad, unsigned long long adlen,
                        const unsigned char *npub,
                        const unsigned char *k);

#endif
HEOF
fi

# Compile all .c files in the current directory (cli.c plus the copied
# reference sources) into a single binary.
SRCS=$(ls *.c)
gcc -O2 -std=c99 -o cli $SRCS -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
