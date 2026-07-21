#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract SANDstorm sources. The original csrc.nist.gov host
# no longer serves the Round-1 submission archive, so we pull the Wayback
# Machine snapshot of the original NIST URL.
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20100528045238if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/SANDstorm.zip"
unzip SANDstorm.zip

# Download the v2 update patch, which fixes a long-message hashing bug
# and an erroneously-enabled assembly declaration. Per README_v2.txt the
# v2 SHA3_ref.h replaces the equivalents in the Reference_Implementation,
# Optimized_32bit and Optimized_64bit trees; since we build against
# Reference_Implementation, we only overlay SHA3_ref.h. (SHA3api_opt.c is
# not shipped in Reference_Implementation -- that tree uses SHA3api_ref.c
# instead.)
# wget https://csrc.nist.rip/groups/ST/hash/sha-3/Round1/documents/SANDstormUpdate.zip
unzip SANDstormUpdate.zip

# Apply the patch overlay (the NIST zip ships the file read-only).
chmod -R u+w SANDstorm/SANDstorm/Reference_Implementation
cp SANDstorm/SHA3_ref.h \
   SANDstorm/SANDstorm/Reference_Implementation/SHA3_ref.h

# Copy reference implementation source files.
cp SANDstorm/SANDstorm/Reference_Implementation/SHA3api_ref.c \
   SANDstorm/SANDstorm/Reference_Implementation/SHA3api_ref.h \
   SANDstorm/SANDstorm/Reference_Implementation/SHA3_ref.h \
   .

# Compile the CLI.
# SHA3api_ref.h has include guards; cli.c uses its own fallback extern
# declarations, so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c SHA3api_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
