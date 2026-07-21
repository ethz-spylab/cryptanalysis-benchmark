#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf "romulus" "vendored-romulus.tar.gz"
git clone --depth 1 "https://github.com/romulusae/romulus" "romulus"
find "romulus" -name .git -prune -exec rm -rf {} +
tar czf "vendored-romulus.tar.gz" "romulus"
rm -rf "romulus"
