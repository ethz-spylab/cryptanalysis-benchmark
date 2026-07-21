#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# wget -q https://www.schneier.com/wp-content/uploads/2015/03/2fsh-AES-2.zip
mkdir -p upstream
unzip -q -o 2fsh-AES-2.zip -d upstream
tar -xf upstream/twofish-dos-refc.tar -C upstream

REF="upstream/Twofish"
# Headers use uppercase names in the archive; ship them lower-case so the
# `#include "aes.h"` etc. in TWOFISH.C resolve on a case-sensitive filesystem.
cp "$REF/TWOFISH.C" twofish.c
cp "$REF/TABLE.H"   table.h
cp "$REF/AES.H"     aes.h
cp "$REF/DEBUG.H"   debug.h
cp "$REF/PLATFORM.H" platform.h

for f in twofish.c table.h aes.h debug.h platform.h; do
  tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

# aes.h uses `#include "platform.h"` with a lowercase name already, so just
# make sure TWOFISH.C's other includes also resolve.
sed -i 's|"aes.h"|"aes.h"|; s|"table.h"|"table.h"|; s|"debug.h"|"debug.h"|' twofish.c

# PLATFORM.H only sets LittleEndian/ALIGN32 when `_M_IX86` is defined, so set
# it on the command line; the source is otherwise portable.
gcc -O2 -D_M_IX86 -o cli cli.c twofish.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
