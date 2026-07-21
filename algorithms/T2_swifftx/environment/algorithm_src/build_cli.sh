#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SWIFFTX sources (Round 1 submission).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/SWIFFTX.zip
unzip SWIFFTX.zip

# Copy reference implementation source files. The folder name contains a
# space ("Reference Implementation"), so we quote it. Tester.c,
# ProduceRandomIV.c, ProduceRandomSBox.c are KAT / table-generator
# drivers and are not needed for the CLI build. We deliberately do NOT
# copy the upstream stdbool.h / stdint.h / inttypes.h stubs -- they
# conflict with the system headers on modern toolchains.
cp "SWIFFTX/Reference Implementation/SHA3.c" \
   "SWIFFTX/Reference Implementation/SHA3.h" \
   "SWIFFTX/Reference Implementation/SWIFFTX.c" \
   "SWIFFTX/Reference Implementation/SWIFFTX.h" \
   .

# Compile the CLI.
# SHA3.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
# -fcommon: SHA3.h declares HAIFA_IV_* / SALT_VALUE as tentative (non-extern)
# definitions; gcc >=10 defaults to -fno-common which turns those into strong
# definitions, colliding with the real ones in SHA3.c. Keep the legacy common-
# symbol behavior so the linker merges them.
gcc -O3 -std=c99 -fcommon -o cli \
    cli.c SHA3.c SWIFFTX.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
