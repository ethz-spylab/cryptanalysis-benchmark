#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# The HPC reference implementation is checked in under vendor/ (line endings
# normalised to LF; otherwise byte-identical to the Schneier-mirror HPC.zip).
# We do NOT download it at build time.
#
# Restore a fresh working copy from vendor/ on every build so the patch step
# is deterministic and the script is safe to re-run.
rm -rf HPC std_defs.h
cp -r vendor/HPC .
cp vendor/std_defs.h .

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

# Build. hpc.c lives at HPC/hpc.c and includes "../std_defs.h", so we add
# the current directory to the include path so that resolves correctly.
gcc -O3 -o cli cli.c HPC/hpc.c -I.

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
