#!/bin/bash
# LUOV scaling-down variant generator (T1->T2 reclassified; bands DERIVED from
# source analysis, no proposal file — see algorithm_scaling_down/IMPLEMENTATION_NOTES.md
# "Part 3 — T1->T2 reclassified").
#
# LUOV = Lifted Unbalanced Oil & Vinegar multivariate signature. Shipped set:
# luov-8-63-256 = field GF(2^8) (FIELD_SIZE=8, lifted from GF(2)), m=OIL_VARS=63
# equations, v=VINEGAR_VARS=256 vinegar vars, n=m+v=319 total variables.
#
# Knob: the MQ system size (OIL_VARS = m, VINEGAR_VARS = v) in
#   LUOV/Reference_Implementation/luov-8-63-256/parameters.h
# The direct algebraic forgery fixes n-m variables and solves m quadratic
# equations in m unknowns over GF(2^8); its cost is governed by m = OIL_VARS.
# Reducing m makes forgery feasible; v is scaled ~4x m (base ratio 256/63~=4.06)
# to preserve the unbalanced v>m UOV structure so key-recovery stays the more
# expensive path. FIELD_SIZE=8 and SHAKENUM=128 are kept, so the GF(2^8) tables
# and SHAKE128 expansion stay valid.
#
#   Hard   m=56 v=224 -> n=280   (~2^56-2^80, best-effort MQ forgery cost)
#   Medium m=40 v=160 -> n=200   (~2^40-2^60)
#   Easy   m=24 v=96  -> n=120   (~2^24-2^40)
#
# Every band keeps m <= 64, matching the shipped m=63 Bitcontainer code path
# (`#if OIL_VARS > 64`). All CRYPTO_* sizes in api.h and every internal buffer
# re-derive at compile time from OIL_VARS/VINEGAR_VARS, so only parameters.h is
# patched.
#
# Concealment: patch artifacts live in ./variant_patches/ (algorithm ROOT, a
# sibling of environment/), so they never enter the Docker build context and are
# invisible to the agent. The weakened source is repacked into the SAME archive
# name (LUOV.zip), keeping build_cli.sh and the folder name luov-8-63-256
# pristine. The committed original archive is never modified.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LUOV.zip"
# parameters.h relative to the archive's top-level directory:
PARAMS_REL="LUOV/Reference_Implementation/luov-8-63-256/parameters.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_luov.py"

# band | folder-encoding | "m v"
VARIANTS=(
  "easy|m24v96|24 96"
  "medium|m40v160|40 160"
  "hard|m56v224|56 224"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PARAMS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$PATCHER" "$TMP/$PARAMS_REL" $PARAMS

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"

  # Variants are challenge tasks: keep only the solution placeholder (the base
  # folder already ships just solution/TODO.md, carried over by the cp -r above).
done
