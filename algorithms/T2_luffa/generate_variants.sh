#!/bin/bash
# Approach A (reduce the Luffa permutation step count) per
# algorithm_scaling_down/nist_sha3/luffa.txt
#   Hard LUFFA_STEPS=4  Medium LUFFA_STEPS=3  Easy LUFFA_STEPS=2  (shipped full = 8)
#
# The step loop `for(i=0;i<8;i++){ step(state,c); }` lives only inside rnd() in
# Luffa/Reference Implementation/luffa.c, which build_cli.sh copies out after
# unzipping Luffa.zip. Every permutation invocation (message absorption, blank
# rounds, output squeeze) routes through rnd(), so reducing this single loop
# bound uniformly weakens the whole hash. Round constants come from the
# genconstant() LFSR (not a fixed-length table), so a reduced step count is
# self-consistent.
#
# Patch artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent. The weakened source is repacked into the SAME archive name so
# build_cli.sh stays pristine. The committed original archive is never modified.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Luffa.zip"

# band|param-encoding|patch-file
VARIANTS=(
  "easy|s2|variant_easy.patch"
  "medium|s3|variant_medium.patch"
  "hard|s4|variant_hard.patch"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PATCH <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  # diff paths are a/Luffa/... ; -p1 strips a/ leaving Luffa/... relative to $TMP
  patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$PATCH"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
