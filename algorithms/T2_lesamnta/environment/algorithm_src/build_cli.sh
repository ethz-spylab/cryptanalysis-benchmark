#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Lesamnta sources
unzip -o Lesamnta.zip

# Copy reference implementation source files (note the SPACE in the dir name)
cp "Nist_submission_Lesamnta_October2008/Reference Implementation/lesamnta_refer.c" \
   "Nist_submission_Lesamnta_October2008/Reference Implementation/lesamnta_refer.h" \
   .

# Compile the CLI
# lesamnta_refer.h provides the standard NIST SHA-3 API (Hash, Init, Update, Final).
gcc -O3 -std=c99 -o cli \
    cli.c lesamnta_refer.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
