#!/bin/bash
set -e

cd "$(dirname "$0")"

gcc -O3 -o cli cli.c chacha.c

echo "Build complete. CLI binary created at: $(pwd)/cli"
