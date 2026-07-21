#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

wget --tries=5 --waitretry=10 --retry-connrefused -O "mceliece-20221023.tar.gz" "https://classic.mceliece.org/nist/mceliece-20221023.tar.gz"

rm -rf "XKCP" "vendored-XKCP.tar.gz"
git clone --depth 1 --recurse-submodules "https://github.com/XKCP/XKCP.git" "XKCP"
(cd "XKCP" && git submodule update --init --recursive)
find "XKCP" -name .git -prune -exec rm -rf {} +
tar czf "vendored-XKCP.tar.gz" "XKCP"
rm -rf "XKCP"
