#!/bin/bash
# Scaling-down variants for KCL (OKCN-MLWE) per algorithm_scaling_down/nist_pqc/kcl.txt
#
# Knob: effective Module-LWE dimension n_eff = MLWE_N * MLWE_ELL in
#   OKCN_AKCN_CNKE/Reference_Implementation/kem/OKCN-MLWE/ref/parameter.h
#   (shipped: MLWE_N=256, LOG2N=8, MLWE_ELL=3  ->  n_eff=768).
#
#   Hard   MLWE_N=128 LOG2N=7 MLWE_ELL=3  -> n_eff=384  (beta~269, ~2^60-2^80)
#   Medium MLWE_N=256 LOG2N=8 MLWE_ELL=1  -> n_eff=256  (beta~179, ~2^40-2^60)
#   Easy   MLWE_N=64  LOG2N=6 MLWE_ELL=3  -> n_eff=192  (beta~134, ~2^30-2^40)
#
# Reducing the ring degree MLWE_N requires regenerating the four hard-wired NTT
# constant tables in polynomial.c for the new degree; variant_patches/patch_kcl.py
# edits parameter.h and regenerates those tables (its generator reproduces the
# shipped n=256 tables byte-for-byte, so it is correct for any admissible degree).
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so they are never part of the Docker build context and stay
# invisible to the agent. The weakened source is repacked into the SAME archive
# name so build_cli.sh stays pristine. The committed original archive under
# $SCRIPT_DIR is never modified (we only ever repack into $VARIANT_DIR).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="OKCN_AKCN_CNKE.zip"
EXTRACT_ROOT="OKCN_AKCN_CNKE"
REF_REL="Reference_Implementation/kem/OKCN-MLWE/ref"
PATCHER="$SCRIPT_DIR/variant_patches/patch_kcl.py"

# band|encoding|MLWE_N|LOG2N|MLWE_ELL
VARIANTS=(
  "easy|n64l3|64|6|3"
  "medium|n256l1|256|8|1"
  "hard|n128l3|128|7|3"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC N LOG2N ELL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$REF_REL" "$N" "$LOG2N" "$ELL"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
  echo "Generated $VARIANT_DIR (MLWE_N=$N LOG2N=$LOG2N MLWE_ELL=$ELL, n_eff=$((N*ELL)))"
done
