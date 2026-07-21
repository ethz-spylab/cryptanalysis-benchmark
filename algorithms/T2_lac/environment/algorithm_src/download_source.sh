#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf "LAC" "vendored-LAC.tar.gz"
git clone "https://github.com/zhenfeizhang/LAC.git" "LAC"
(cd "LAC" && git checkout c0453fd1b5c803dd9b4fc5142be42c242da78034)
find "LAC" -name .git -prune -exec rm -rf {} +
tar czf "vendored-LAC.tar.gz" "LAC"
rm -rf "LAC"
