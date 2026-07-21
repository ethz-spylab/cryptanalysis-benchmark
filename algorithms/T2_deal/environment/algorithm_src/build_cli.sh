#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract the reference implementation.
# wget -q https://www.schneier.com/wp-content/uploads/2015/03/DEAL-2.zip
mkdir -p upstream
unzip -q -o DEAL-2.zip -d upstream

# Bring the cipher and its shared header alongside cli.c.
cp upstream/deal.c cipher.c
cp upstream/std_defs.h .

# Normalize Windows line endings that break backslash-continued macros.
sed -i 's/\r$//' cipher.c std_defs.h
tr -d '\r' < cipher.c > cipher.c.tmp && mv cipher.c.tmp cipher.c
tr -d '\r' < std_defs.h > std_defs.h.tmp && mv std_defs.h.tmp std_defs.h

# The upstream source expects std_defs.h to live one directory above.
sed -i 's|"../std_defs.h"|"std_defs.h"|' cipher.c

# DEAL uses single-DES as its Feistel round function. The vendored DEAL-2.zip
# ships only deal.c + std_defs.h; the DES dependency lived in a sibling des/
# directory of Gladman's full distribution that is NOT part of the archive.
# We provide a self-contained, FIPS-46-exact DES (des_round.h, validated
# against the standard test vector) and:
#   - redirect the missing "../des/des.h" include to it, and
#   - undefine MODIFIED_DES so deal.c uses the full DES primitive (with IP/FP)
#     as its round function and never references des_ecm / ip() / fp() (the
#     "With unmodified DES" DEAL variant documented in deal.c's own header).
# These are include-path / build-macro normalizations only; the cipher logic in
# deal.c is left untouched.
sed -i 's|#include "../des/des.h"|#include "des_round.h"|' cipher.c
sed -i 's|^#define MODIFIED_DES|/* MODIFIED_DES disabled: use full DES round function */|' cipher.c

# The Gladman AES-era reference code assumes `unsigned long` is exactly 32 bits.
# On 64-bit Linux that assumption is false, so narrow the typedefs to
# 32-bit-exact `unsigned int` / `signed int`.
sed -i 's/unsigned long   u4byte/unsigned int    u4byte/' std_defs.h
sed -i 's/signed long     s4byte/signed int      s4byte/' std_defs.h

gcc -O2 -o cli cli.c cipher.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
