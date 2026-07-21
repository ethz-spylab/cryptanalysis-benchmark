#!/bin/bash
set -e

cd "$(dirname "$0")"

# Fix Windows line endings in the .inc file if present
sed 's/\r$//' decryption_4bit.inc > decryption_4bit_fixed.inc
cp decryption_4bit_fixed.inc decryption_4bit.inc
rm decryption_4bit_fixed.inc

g++ -O3 -o cli cli.cpp

echo "Build complete. CLI binary created at: $(pwd)/cli"
