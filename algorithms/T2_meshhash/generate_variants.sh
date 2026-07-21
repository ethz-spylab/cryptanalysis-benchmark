#!/bin/bash
# Approach A (reduce number_of_pipes) per algorithm_scaling_down/nist_sha3/meshhash.txt
#   Hard pipes=4 (state 256b, 4 rounds/block)
#   Medium pipes=3 (state 192b, 3 rounds/block)
#   Easy pipes=2 (state 128b, 2 rounds/block)
# Shipped full-strength default: ComputeNumberOfPipes(256) = (256+63)/64 + 1 = 5 pipes.
#
# MeshHash has no separate round-count constant: the single structural knob
# number_of_pipes governs both the internal-state width (64 bits/pipe) and the
# per-block diffusion depth (one normal_round/pipe). It is fixed at run time by
# ComputeNumberOfPipes() in MeshHash/Reference_Implementation/meshhash.c under the
# clamps MIN_NUMBER_OF_PIPES / NUMBER_OF_EXTRA_PIPES in meshhash.h. The patcher
# forces a fixed return and lowers MIN_NUMBER_OF_PIPES (and COUNTER_LENGTH, to keep
# the header's COUNTER_LENGTH <= MIN_NUMBER_OF_PIPES invariant). The squeeze emits
# hashbitlen/8 bytes independently of the pipe count, so the 256-bit digest is
# preserved and the variants stay drop-in comparable.
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enters the Docker build context => invisible to the agent).
# The weakened source is repacked into the same MeshHash.zip archive name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="MeshHash.zip"
EXTRACT_ROOT="MeshHash"                          # top-level dir inside MeshHash.zip
TARGET_REL="Reference_Implementation"            # dir holding meshhash.c / meshhash.h

# band|pipes
VARIANTS=(
  "easy|2"
  "medium|3"
  "hard|4"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND PIPES <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_p${PIPES}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_meshhash.py" \
          "$TMP/$EXTRACT_ROOT/$TARGET_REL" "$PIPES"
  # Repack with the same internal layout build_cli.sh expects (top dir MeshHash/...).
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Remove patch artifacts from the variant so nothing leaks into the task.
  rm -rf "$VARIANT_DIR/variant_patches"
done
