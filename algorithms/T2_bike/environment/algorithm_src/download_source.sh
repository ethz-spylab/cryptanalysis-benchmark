#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

wget --tries=5 --waitretry=10 --retry-connrefused -O "Reference_Implementation.2024.10.10.1.zip" "https://bikesuite.org/files/v5.2/Reference_Implementation.2024.10.10.1.zip"
