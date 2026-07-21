#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Vortex sources (the "Update" package -- the update
# only restructures API plumbing; the compression function is unchanged
# from the original Round-1 submission).
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/VortexUpdate.zip
unzip VortexUpdate.zip

# Copy reference implementation source files. We skip vortex_main.c
# because it defines its own main() for the NIST KAT driver; our cli.c
# provides main() instead.
SRC="VortexUpdate/Reference_Implementation/SHA3_vortex"
cp "$SRC/SHA3api_ref.c" \
   "$SRC/SHA3api_ref.h" \
   "$SRC/vortex_core.c" \
   "$SRC/vortex_core.h" \
   "$SRC/vortex_misc.c" \
   "$SRC/vortex_misc.h" \
   "$SRC/vortex_tables.c" \
   "$SRC/int_types.h" \
   .

# Compile the CLI.
# SHA3api_ref.h provides the standard NIST SHA-3 API (Hash, Init, Update,
# Final) and has proper include guards. We do NOT use -include because
# cli.c's own fallback extern declarations (behind
# #ifndef HASH_API_ALREADY_INCLUDED) already match the NIST API.
# SHA3api_ref.c uses malloc/free/perror without including <stdlib.h>/
# <stdio.h>, so we force-include them to silence the
# implicit-declaration warnings.
gcc -O3 -std=c99 -D_POSIX_C_SOURCE=200809L \
    -include stdlib.h -include stdio.h -o cli \
    cli.c SHA3api_ref.c vortex_core.c vortex_misc.c vortex_tables.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
