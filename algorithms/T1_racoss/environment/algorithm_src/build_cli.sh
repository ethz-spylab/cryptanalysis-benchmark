#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract GuessAgain sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/RaCoSS.zip
unzip RaCoSS.zip

# Install necessary dependencies
apt-get update

# Copy source files from Reference_Implementation to the current directory
# (excluding PQCgenKAT_kem.c which has its own main function)
cp RaCoSS/Reference_Implementation/* .

# Apply some bug fixes.
sed -i 's/for( i=0 ; i<(RACOSS_N\/8) ; i++ )/for( i=0 ; i<(RACOSS_N) ; i++ )/' sign.c
# Fix memory leak in wrhf(): free allocated array I before returning
sed -i '/c\[I\[i\]\] = 1;/{n;a\\tfree( I );
}' sign.c
# Fix memory leak in crypto_sign_open(): free allocated buffer b before returning
sed -i '/c2\[i\] != c\[i\]/,/memset/{/memset/i\\t\t\tfree( b );
}' sign.c
sed -i '/Check wethere/,/return 0;/{/return 0;/i\\tfree( b );
}' sign.c

# Compile the CLI
gcc -O3 -o cli cli.c rng.c sha3.c sign.c -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"

# Clean up downloaded archives
# rm -rf RaCoSS.zip RaCoSS
