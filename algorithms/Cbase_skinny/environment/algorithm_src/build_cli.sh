#!/bin/bash
set -e

cd "$(dirname "$0")"

# Work on a copy to preserve the original
cp skinny_reference.c skinny_build.c

# Fix Windows line endings
sed -i 's/\r$//' skinny_build.c

# Remove DEBUG define
sed -i 's/^#define DEBUG 1//' skinny_build.c

# Remove FILE* fic global
sed -i '/^FILE\* fic;$/d' skinny_build.c

# Remove display_matrix function
sed -i '/^void display_matrix/,/^}$/d' skinny_build.c

# Remove display_cipher_state function
sed -i '/^void display_cipher_state/,/^}$/d' skinny_build.c

# Remove TestVectors function
sed -i '/^void TestVectors/,/^}$/d' skinny_build.c

# Remove main function
sed -i '/^int main()/,/^}$/d' skinny_build.c

# Strip #ifdef DEBUG ... #endif blocks
sed -i '/#ifdef DEBUG/,/#endif/d' skinny_build.c

gcc -O3 -o cli cli.c skinny_build.c

echo "Build complete. CLI binary created at: $(pwd)/cli"
