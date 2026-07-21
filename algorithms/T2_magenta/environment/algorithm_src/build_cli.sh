#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Always start from a fresh extraction so the patch step is deterministic
# and the script is safe to re-run.
rm -rf MAGENTA std_defs.h
# wget https://www.schneier.com/wp-content/uploads/2015/03/MAGENTA-2.zip

# The zip ships magenta.c and std_defs.h side-by-side at its root, but
# magenta.c contains `#include "../std_defs.h"` (an artefact of Gladman's
# original dev tree). Place magenta.c one directory below std_defs.h so
# that include path resolves naturally.
mkdir MAGENTA
unzip -d MAGENTA MAGENTA-2.zip
mv MAGENTA/std_defs.h .

# The Schneier-mirror zip ships files with CR LF (and sometimes CR CR LF)
# line endings; normalise to LF so the unified-diff patches apply cleanly.
tr -d '\r' < std_defs.h > std_defs.h.tmp && mv std_defs.h.tmp std_defs.h
tr -d '\r' < MAGENTA/magenta.c > MAGENTA/magenta.c.tmp && mv MAGENTA/magenta.c.tmp MAGENTA/magenta.c

# Apply portability patches. See CHANGES.md for the rationale of each patch.
apply_patch() {
    local patch_file="$1"
    if patch -p1 -R --dry-run --silent < "$patch_file" >/dev/null 2>&1; then
        echo "Skipping $patch_file (already applied)"
    else
        patch -p1 < "$patch_file"
    fi
}

apply_patch patches/std_defs.h.patch

# Build. magenta.c lives at MAGENTA/magenta.c and includes "../std_defs.h",
# so we add the current directory to the include path so that resolves.
gcc -O3 -o cli cli.c MAGENTA/magenta.c -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
