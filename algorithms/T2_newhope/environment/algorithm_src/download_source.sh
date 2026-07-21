#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf "newhope" "vendored-newhope.tar.gz"
git clone "https://github.com/newhopecrypto/newhope.git" "newhope"
(cd "newhope" && git checkout 276551a21be7c3c38f80d619ddea2feb2e1572e6)
find "newhope" -name .git -prune -exec rm -rf {} +
tar czf "vendored-newhope.tar.gz" "newhope"
rm -rf "newhope"
