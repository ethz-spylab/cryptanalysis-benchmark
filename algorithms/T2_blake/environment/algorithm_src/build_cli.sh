#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract BLAKE sources (Round 3 final submission).
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20120813004915if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round3/documents/Blake_FinalRnd.zip"
unzip Blake_FinalRnd.zip

# The NIST zip ships read-only copies of blake_ref.c / blake_ref.h; make
# them writeable so the post-Round-3 designer fix (see below) can overwrite
# them in place.
chmod -R u+w Blake_FinalRnd

# Copy reference implementation source files.
cp Blake_FinalRnd/Reference_Implementation/blake_ref.c \
   Blake_FinalRnd/Reference_Implementation/blake_ref.h \
   .

# Overlay the designer's post-submission fix, published at
# https://www.aumasson.jp/blake/ . These files supersede the equally-named
# files shipped in Blake_FinalRnd.zip.
# wget -O blake_ref.c https://www.aumasson.jp/blake/blake_ref.c
# wget -O blake_ref.h https://www.aumasson.jp/blake/blake_ref.h

# Compile the CLI.
# blake_ref.h has no include guards, but cli.c never includes it directly
# (it uses its own fallback extern declarations of the NIST SHA-3 API
# guarded by #ifndef HASH_API_ALREADY_INCLUDED), so -include is not needed.
gcc -O3 -std=c99 -o cli \
    cli.c blake_ref.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
