#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# wget -q https://www.schneier.com/wp-content/uploads/2015/03/Mars-AES-2.zip
mkdir -p upstream
unzip -q -o Mars-AES-2.zip -d upstream
tar -xf upstream/mars-dos-refc.tar -C upstream

REF="upstream/Mars"
cp "$REF/mars-ref.c" cipher.c
cp "$REF/aes.h"      cipher.h

for f in cipher.c cipher.h; do
  tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

sed -i 's|"aes.h"|"cipher.h"|' cipher.c

# WORD is typedef'd as `unsigned long`, 64 bits on 64-bit Linux. The reference
# code casts `(WORD *)` over byte buffers and relies on WORD being exactly 32
# bits. Pin it to a fixed-width 32-bit type.
sed -i 's/typedef unsigned long WORD;/#include <stdint.h>\ntypedef uint32_t WORD;/' cipher.h

gcc -O2 -o cli cli.c cipher.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
