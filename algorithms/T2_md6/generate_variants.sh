#!/bin/bash
# Approach A (reduce the MD6 round count r) per algorithm_scaling_down/nist_sha3/md6.txt
#   Hard r=24   Medium r=20   Easy r=16   (shipped full-strength default: r = 40 + d/4 = 104)
#
# r is computed by md6_default_r() in MD6/Reference_Implementation/md6_mode.c
# (line `r = 40 + (d/4);`). The patcher replaces that body with a fixed small
# constant, so every md6_compress call iterates fewer feedback rounds. Block
# sizes, tree mode, and I/O format are untouched (0 <= r <= md6_max_r = 255).
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enters the Docker build context => invisible to the
# agent). The weakened source is repacked into the same md6.zip archive name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="md6.zip"
EXTRACT_ROOT="MD6"                                  # top-level dir inside md6.zip
TARGET_REL="Reference_Implementation/md6_mode.c"    # file holding md6_default_r

# band|r-value
VARIANTS=(
  "easy|16"
  "medium|20"
  "hard|24"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND RVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_r${RVAL}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_md6.py" \
          "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$RVAL"
  # Repack with the same internal layout build_cli.sh expects (top dir MD6/...).
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Remove patch artifacts from the variant so nothing leaks into the task.
  rm -rf "$VARIANT_DIR/variant_patches"
done
