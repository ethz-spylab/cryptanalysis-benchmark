#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# wget -q https://www.schneier.com/wp-content/uploads/2015/03/Serp-AES-2.zip
mkdir -p upstream
unzip -q -o Serp-AES-2.zip -d upstream
tar -xf upstream/serpent-dos-refc.tar -C upstream

REF="upstream/Serpent"
cp "$REF/serpent-ref.c"      .
cp "$REF/serpent-ref.h"      .
cp "$REF/serpent-aux.c"      .
cp "$REF/serpent-aux.h"      .
cp "$REF/serpent-api.h"      .
cp "$REF/serpent-tables.h"   .

# Normalize line endings that break backslash-continued macros.
for f in serpent-ref.c serpent-ref.h serpent-aux.c serpent-aux.h serpent-api.h serpent-tables.h; do
  tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

# WORD is typedef'd as `unsigned long`, which is 64 bits on 64-bit Linux and
# leaks high bits through the cipher's rotations. Pin it to 32-bit exact.
sed -i 's/typedef unsigned long WORD;/#include <stdint.h>\ntypedef uint32_t WORD;/' serpent-api.h

gcc -O2 -o cli cli.c serpent-ref.c serpent-aux.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
