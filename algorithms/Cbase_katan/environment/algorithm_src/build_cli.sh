#!/bin/bash
set -e

cd "$(dirname "$0")"

# Work on a copy to preserve the original
cp katan.c katan_build.c

# Remove test_values() function and main() function
sed -i '/^void test_values/,/^}$/d' katan_build.c
sed -i '/^int main /,/^}$/d' katan_build.c

gcc -O3 -o cli cli.c katan_build.c

echo "Build complete. CLI binary created at: $(pwd)/cli"
