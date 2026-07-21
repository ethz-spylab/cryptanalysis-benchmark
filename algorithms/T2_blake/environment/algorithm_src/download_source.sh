#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

wget --tries=5 --waitretry=10 --retry-connrefused -O "Blake_FinalRnd.zip" "https://web.archive.org/web/20120813004915if_/http://csrc.nist.gov/groups/ST/hash/sha-3/Round3/documents/Blake_FinalRnd.zip"

wget --tries=5 --waitretry=10 --retry-connrefused -O "blake_ref.c" "https://www.aumasson.jp/blake/blake_ref.c"

wget --tries=5 --waitretry=10 --retry-connrefused -O "blake_ref.h" "https://www.aumasson.jp/blake/blake_ref.h"
