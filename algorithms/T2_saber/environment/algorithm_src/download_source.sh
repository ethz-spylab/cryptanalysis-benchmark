#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf "SABER" "vendored-SABER.tar.gz"
git clone "https://github.com/KULeuven-COSIC/SABER.git" "SABER"
(cd "SABER" && git checkout f7f39e4db2f3e22a21e1dd635e0601caae2b4510)
find "SABER" -name .git -prune -exec rm -rf {} +
tar czf "vendored-SABER.tar.gz" "SABER"
rm -rf "SABER"
