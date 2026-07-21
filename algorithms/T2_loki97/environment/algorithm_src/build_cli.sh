#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Always start from a fresh extraction so the patch step is deterministic
# and the script is safe to re-run.
rm -rf cref loki97.c loki97.h
# wget https://www.schneier.com/wp-content/uploads/2015/03/LOKI97-2.zip
unzip LOKI97-2.zip

# Lift the two reference-implementation source files we need to the top level.
cp cref/loki97.c cref/loki97.h .

# Apply portability patches. See CHANGES.md for the rationale of each patch.
apply_patch() {
    local patch_file="$1"
    if patch -p1 -R --dry-run --silent < "$patch_file" >/dev/null 2>&1; then
        echo "Skipping $patch_file (already applied)"
    else
        patch -p1 < "$patch_file"
    fi
}

apply_patch patches/loki97.h.patch

# Build. -Wno-implicit-int / -Wno-implicit-function-declaration tolerate the
# K&R-style declarations in the 1998 reference (e.g. `register s;` in f()).
gcc -O3 -std=gnu99 -Wno-implicit-int -Wno-implicit-function-declaration \
    -o cli cli.c loki97.c -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
