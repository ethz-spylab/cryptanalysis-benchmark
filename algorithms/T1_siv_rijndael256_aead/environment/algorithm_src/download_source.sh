#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

wget --tries=5 --waitretry=10 --retry-connrefused -O "siv-rijndael256.zip" "https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/round-1/submissions/siv-rijndael256.zip"
