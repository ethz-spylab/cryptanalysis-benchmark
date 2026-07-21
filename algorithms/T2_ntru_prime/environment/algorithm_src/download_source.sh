#!/bin/bash
# Re-download upstream sources for this algorithm.
# Invoked by generate_harbor_tasks.sh --download-sources from within the
# generated task folder, replacing the vendored archives in place.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

wget --tries=5 --waitretry=10 --retry-connrefused -O "ntruprime-20201007.tar.gz" "https://ntruprime.cr.yp.to/nist/ntruprime-20201007.tar.gz"
