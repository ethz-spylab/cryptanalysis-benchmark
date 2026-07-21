#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Dynamic SHA (Round 1) sources.
# NOTE: the upstream archive filename is misspelled as "DyamicSHA.zip".
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/DyamicSHA.zip
unzip -o DyamicSHA.zip

# Copy the reference implementation source.
# Dynamic SHA's reference implementation is header-only: dsha_ref.h contains the
# full NIST SHA-3 API (Hash/Init/Update/Final) plus the constant tables and the
# sha32_compile/sha64_compile compression functions. There is no separate .c.
cp "DynamicSHA/Reference Implementation/dsha_ref.h" .

# Provide a single translation unit that pulls in the header-only reference
# implementation. We generate this wrapper here (we never edit upstream source);
# it is the only place dsha_ref.h is compiled, so the lack of include guards in
# the header causes no redefinition errors.
cat > dsha_ref_impl.c <<'EOF'
#include "dsha_ref.h"
EOF

# Compile the CLI.
# We do NOT use -include dsha_ref.h: the header lacks include guards and is
# already compiled via dsha_ref_impl.c. cli.c uses its own fallback extern
# declarations (behind #ifndef HASH_API_ALREADY_INCLUDED) which match the
# NIST SHA-3 API types.
gcc -O3 -std=c99 -o cli \
    cli.c dsha_ref_impl.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
