#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf "DryGASCON" "vendored-DryGASCON.tar.gz"
git clone --depth 1 "https://github.com/sebastien-riou/DryGASCON" "DryGASCON"
find "DryGASCON" -name .git -prune -exec rm -rf {} +
tar czf "vendored-DryGASCON.tar.gz" "DryGASCON"
rm -rf "DryGASCON"
