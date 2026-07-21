#!/bin/bash
# Approach A (reduce the digest/structural size n = wordCount) per
# algorithm_scaling_down/nist_sha3/blender.txt.
#
# Blender's best published attack (the slice/structural collision) costs
# 10 * 2^(n/4), governed solely by the output/word structure n; the
# finalization round-like knob (minimumRounds/roundsToGo) does NOT enter the
# attack curve, so n is the scaling target.
#
#   Easy   (2^30-2^40):  n = 128  (16-bit words, wordCount = 8)  ~ 2^35
#   Medium (2^40-2^60):  n = 192  (32-bit words, wordCount = 6)  ~ 2^51
#   Hard   (2^60-2^80):  n = 288  (32-bit words, wordCount = 9)  ~ 2^75
#
# DEVIATION: the proposal pins Hard at n = 256, but 256 is exactly the shipped
# cli.c default (`args.hashbitlen = 256`), so a 256 variant would be
# byte-identical to the base T2_blender and is therefore not a valid (distinct,
# weakened) variant. n = 288 is the next supported 32-bit-word digest size
# (wordCount = 9, 6 <= 9 <= 10), lands at ~2^75 squarely inside the Hard band,
# and is distinct from the base default. All three n values sit on supported
# Init paths in Blender.c (`w = hashbitlen / {16,32,64}`, 6 <= w <= 10).
#
# The knob is NOT inside Blender.zip -- it is the runtime CLI default in cli.c,
# which the HashCollisionGame oracle uses because it calls `cli hash` without a
# --hashbitlen flag. So we patch cli.c directly in the variant copy; the
# committed Blender.zip archive and build_cli.sh are never touched.
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enters the Docker build context => invisible to the
# agent), and is removed from each generated variant.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
TARGET_REL="cli.c"   # holds the default --hashbitlen that pins n

# band|hashbitlen
VARIANTS=(
  "easy|128"
  "medium|192"
  "hard|288"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND NVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_n${NVAL}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  # Patch the CLI default digest size directly in the variant's cli.c.
  python3 "$SCRIPT_DIR/variant_patches/patch_blender.py" \
          "$VARIANT_DIR/$SRC_REL/$TARGET_REL" "$NVAL"

  # Remove patch artifacts from the variant so nothing leaks into the task.
  rm -rf "$VARIANT_DIR/variant_patches"
done
