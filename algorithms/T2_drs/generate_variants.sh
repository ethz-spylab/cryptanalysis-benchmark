#!/bin/bash
# Scale-down variant generator for DRS (Diagonal Reduction Signature, NIST PQC R1)
# per algorithm_scaling_down/nist_pqc/drs.txt.
#
# Approach: reduce the lattice dimension _DIM_ (= n) in the level-I header
# DRS/Reference_Implementation/API_H/api.h.128 (build_cli.sh copies it to api.h),
# rescaling the co-dependent secret-row constants (_D_BOUND_=_DIM_, _NB_ONES_,
# _NB_B_, _B_VAL_) and the _DIM_-derived buffer-size macros together.
#
#   Baseline (shipped, NOT emitted): _DIM_=912  D=912 ONES=432 B=16 BVAL=28  ~2^70-2^80
#   Hard   variant: _DIM_=800  D=800 ONES=379 B=14 BVAL=25  ~2^60-2^68
#   Medium variant: _DIM_=608  D=608 ONES=288 B=11 BVAL=19  ~2^40-2^60
#   Easy   variant: _DIM_=456  D=456 ONES=216 B=8  BVAL=14  ~2^30-2^40
# Every band is strictly weaker than the shipped n=912 set; the shipped values
# are never emitted as a variant.
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so it is outside the Docker build context => invisible to the
# agent. The weakened source is repacked into the same DRS.zip name so the
# committed build_cli.sh stays pristine; the committed original archive is never
# touched (we repack into $VARIANT_DIR, never $SCRIPT_DIR).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="DRS.zip"
EXTRACT_ROOT="DRS"
HEADER_REL="Reference_Implementation/API_H/api.h.128"

# band|enc|DIM|D_BOUND|NB_ONES|NB_B|B_VAL|PK|SK|SIG|MSG
VARIANTS=(
  "easy|n456|456|456|216|8|14|1273609|12885|4275|1653"
  "medium|n608|608|608|288|11|19|2264193|22870|5700|2204"
  "hard|n800|800|800|379|14|25|3920001|39481|7500|2900"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC DIM DBOUND NB_ONES NB_B B_VAL PK SK SIG MSG <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$SCRIPT_DIR/variant_patches/patch_drs.py" \
    "$TMP/$EXTRACT_ROOT/$HEADER_REL" \
    "$DIM" "$DBOUND" "$NB_ONES" "$NB_B" "$B_VAL" "$PK" "$SK" "$SIG" "$MSG"

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
