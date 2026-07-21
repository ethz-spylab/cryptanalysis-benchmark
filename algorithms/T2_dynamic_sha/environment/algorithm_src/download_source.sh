#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# The original NIST mirror (csrc.nist.gov / csrc.nist.rip) was unreachable for
# this file, so fall back to the Internet Archive snapshot. Note the upstream
# filename is misspelled as "DyamicSHA.zip".
wget --tries=5 --waitretry=10 --retry-connrefused -O "DyamicSHA.zip" "https://web.archive.org/web/20161219162856id_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/DyamicSHA.zip"
