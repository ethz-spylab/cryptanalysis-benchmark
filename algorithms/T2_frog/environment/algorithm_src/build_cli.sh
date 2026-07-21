#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract the reference implementation.
# wget -q https://www.schneier.com/wp-content/uploads/2015/03/FROGC-2.zip
mkdir -p upstream
unzip -q -o FROGC-2.zip -d upstream

# Bring the cipher and its headers alongside cli.c. The upstream files use
# uppercase names (FROG.C/FROG.H/AES.H) but the sources #include the lowercase
# "frog.h"/"aes.h", so rename on copy. MAIN.C/TESTS.* (which ship their own
# main()) are intentionally left out.
cp upstream/FROG.C frog.c
cp upstream/FROG.H frog.h
cp upstream/AES.H aes.h

# Normalize Windows line endings (the archive is CRLF).
for f in frog.c frog.h aes.h; do
  sed -i 's/\r$//' "$f"
  tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

gcc -O2 -o cli cli.c frog.c

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
