#!/bin/bash
# Approach A (reduce Xbox round count) per algorithm_scaling_down/nist_sha3/waterfall.txt
#   Xbox() in Waterfall/Reference_Implementation/Waterfall.c iterates an
#   S-box-feedback + 1-byte-rotate step 4 times (default). Every message
#   absorption (UpdateStep) and finalization (FinalStep) routes through Xbox(),
#   so it is the single round-like knob that uniformly governs diffusion.
#     Hard XBOX_ROUNDS=3   Medium XBOX_ROUNDS=2   Easy XBOX_ROUNDS=1
#   Each band keeps only the first N unrolled iterations.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The upstream Waterfall.c uses CRLF line endings, so a single
# parameterized binary-safe Python patcher (patch_waterfall.py) is used instead
# of unified-diff patches. Weakened source is repacked into the same archive
# name so build_cli.sh stays pristine. The committed original archive is never
# touched.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Waterfall.zip"
EXTRACT_ROOT="Waterfall"   # top-level dir inside the archive
TARGET_REL="Reference_Implementation/Waterfall.c"   # the file build_cli.sh compiles

# band|param-encoding|xbox-rounds
VARIANTS=(
  "easy|x1|1"
  "medium|x2|2"
  "hard|x3|3"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC ROUNDS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_waterfall.py" \
          "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$ROUNDS"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
