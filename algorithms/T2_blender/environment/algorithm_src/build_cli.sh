#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract Blender sources
unzip -o Blender.zip

# Copy reference implementation source files (dir name contains a space).
# Blender.c includes SHA3api_ref.h which includes Blender.h.
cp "Blender/Reference Implementation/Blender.c" \
   "Blender/Reference Implementation/Blender.h" \
   "Blender/Reference Implementation/SHA3api_ref.h" \
   .

# Compile the CLI
# Blender.c contains an unused benchmark helper timehash() that relies on the
# MSVC x86 intrinsics __cpuid/__rdtsc (unavailable under gcc). It is never called
# from the NIST Hash() API path, so we stub the intrinsics out with no-op macros.
# -fcommon/-fno-strict-aliasing/-w keep this old SHA-3 candidate code building.
gcc -O3 -std=c99 -fcommon -fno-strict-aliasing -w \
    -D'__cpuid(a,b)=' -D'__rdtsc()=0' \
    -o cli \
    cli.c Blender.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
