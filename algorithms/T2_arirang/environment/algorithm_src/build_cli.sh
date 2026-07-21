#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract ARIRANG sources (Round 1 update).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/ARIRANGUpdate.zip
unzip ARIRANGUpdate.zip

# Copy reference implementation source files. The folder name contains a
# space ("Reference Implementation"), so we quote it.
# SHA3api_ref.c implements the NIST SHA-3 API by wrapping the 64-bit
# ARIRANG core; genKAT_Ref64.c is a KAT driver and is not needed.
cp "ARIRANG/Reference Implementation/SHA3api_ref.c" \
   "ARIRANG/Reference Implementation/SHA3api_ref.h" \
   "ARIRANG/Reference Implementation/Arirang_Ref64.c" \
   "ARIRANG/Reference Implementation/Arirang_Ref64.h" \
   .

# SHA3api_ref.c includes "Arirang_ref64.h" (lowercase r) but the header
# is Arirang_Ref64.h — create a case-matched duplicate for case-sensitive FSes.
cp Arirang_Ref64.h Arirang_ref64.h

# Compile the CLI.
# -DUSER_LITTLE_ENDIAN is required because Arirang_Ref64.h's endianness probe
# only recognises _MSC_VER (or the USER_*_ENDIAN override) and errors out
# otherwise.
gcc -O3 -std=c99 -DUSER_LITTLE_ENDIAN -o cli \
    cli.c SHA3api_ref.c Arirang_Ref64.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
