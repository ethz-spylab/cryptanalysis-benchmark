#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract the reference implementation.
# wget -q https://www.schneier.com/wp-content/uploads/2015/03/RC6-AES-2.zip
mkdir -p upstream
unzip -q -o RC6-AES-2.zip -d upstream
tar -xf upstream/rc6-dos-refc.tar -C upstream

cp upstream/RC6/aes.c cipher.c
cp upstream/RC6/aes.h cipher.h

# Normalize Windows line endings that break backslash-continued macros.
tr -d '\r' < cipher.c > cipher.c.tmp && mv cipher.c.tmp cipher.c
tr -d '\r' < cipher.h > cipher.h.tmp && mv cipher.h.tmp cipher.h

# The upstream file includes "aes.h" — rename to the header we just copied.
sed -i 's|"aes.h"|"cipher.h"|' cipher.c

# The reference code assumes `unsigned long` is exactly 32 bits. On 64-bit
# Linux that is false, so we retype it as a fixed-width 32-bit unsigned int.
sed -i 's/unsigned long/uint32_t/g' cipher.c cipher.h
sed -i '1i #include <stdint.h>' cipher.h

gcc -O2 -o cli cli.c cipher.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
