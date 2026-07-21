#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

wget --tries=5 --waitretry=10 --retry-connrefused -O "Blender.zip" "https://web.archive.org/web/20170830023437/http://csrc.nist.gov/groups/ST/hash/sha-3/Round1/documents/Blender.zip"
