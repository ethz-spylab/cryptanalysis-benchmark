#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Primary NIST mirror (csrc.nist.rip). If it is unreachable, fall back to the
# Internet Archive snapshot of the original NIST URL.
wget --tries=5 --waitretry=10 --retry-connrefused -O "hamsi.zip" \
    "https://csrc.nist.rip/groups/ST/hash/sha-3/Round2/documents/Hamsi_Round2.zip" \
  || wget --tries=5 --waitretry=10 --retry-connrefused -O "hamsi.zip" \
    "https://web.archive.org/web/20100528043401id_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round2/documents/Hamsi_Round2.zip"
