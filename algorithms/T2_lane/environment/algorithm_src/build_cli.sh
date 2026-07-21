#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract LANE sources (Round 1 submission). The original
# csrc.nist.gov host no longer serves this archive and the designer's
# project site has gone offline, so we pull the Wayback Machine snapshot
# of the original NIST URL. The LaneUpdate archive is documentation-only
# and does not include updated source code, so we do not apply it.
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20101105222121if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/LANE.zip"
unzip LANE.zip

# Copy reference implementation source files. The folder name contains a
# space ("Reference Implementation"), so we quote it. LANE ships separate
# 256-bit and 512-bit cores, both selected from laneref.c at runtime.
cp "LANE/Reference Implementation/laneref.c" \
   "LANE/Reference Implementation/laneref.h" \
   "LANE/Reference Implementation/laneref256.c" \
   "LANE/Reference Implementation/laneref256.h" \
   "LANE/Reference Implementation/laneref512.c" \
   "LANE/Reference Implementation/laneref512.h" \
   "LANE/Reference Implementation/tables.h" \
   .

# Compile the CLI.
# laneref.h has no include guards, but cli.c never includes it directly
# (it uses its own fallback extern declarations of the NIST SHA-3 API
# guarded by #ifndef HASH_API_ALREADY_INCLUDED), so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c laneref.c laneref256.c laneref512.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
