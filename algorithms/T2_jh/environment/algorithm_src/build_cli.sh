#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract JH sources (Round 3 final submission).
# wget --tries=5 --waitretry=10 --retry-connrefused "https://web.archive.org/web/20120813004915if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round3/documents/JH_FinalRnd.zip"
unzip JH_FinalRnd.zip

# The reference implementation is header-only: jh_ref.h contains the
# full definitions of Hash(), Init(), Update() and Final() (no companion
# .c file). The folder name contains a space, so we quote it.
cp "JH_FinalRnd/Reference Implementation/jh_ref.h" .

# Compile the CLI.
# jh_ref.h has no include guards and is header-only (it both declares and
# defines Hash/Init/Update/Final), so we force-include it once with
# -include (and do not list it as a translation unit). We also pass
# -DHASH_API_ALREADY_INCLUDED so cli.c's fallback typedefs for
# BitSequence/DataLength/HashReturn are suppressed and do not conflict
# with those already provided by jh_ref.h.
gcc -O3 -std=c99 -D_POSIX_C_SOURCE=200809L -DHASH_API_ALREADY_INCLUDED -o cli \
    -include jh_ref.h \
    cli.c \
    -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
