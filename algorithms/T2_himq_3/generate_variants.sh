#!/bin/bash
# HiMQ-3 scaling-down variant generator.
#
# Approach: reduce the multivariate variable/equation counts (V, O1, O2, O3),
# per algorithm_scaling_down/nist_pqc/himq_3.txt. The dominant attack is direct
# Groebner forgery over GF(256), whose cost grows exponentially with the number
# of equations M = O1+O2+O3; V is scaled with M to keep the V/M oil/vinegar
# balance so key-recovery does not become the cheaper path.
#
#   Hard   V=17 O1=9 O2=9 O3=6 -> N=41 M=24 (~2^60-2^80)
#   Medium V=12 O1=5 O2=5 O3=7 -> N=29 M=17 (~2^40-2^60)
#   Easy   V=8  O1=3 O2=3 O3=6 -> N=20 M=12 (~2^30-2^40)
#
# DEVIATION from the proposal's exact layer split: HiMQ-3's sign_layer12 solves a
# cyclic product system over the O1- and O2-sized oil layers via a GF(256)
# square-root trick that is only consistent when the cycle length (the layer
# size) is ODD (the shipped scheme uses O1=O2=15). The proposal's even layer
# splits (e.g. O1=O2=O3=8) build and sign but produce signatures that never
# verify. We therefore keep the proposal's primary security knobs M=O1+O2+O3 and
# N=V+M EXACTLY (so the ~2.9*M security estimate and the named bands are
# unchanged) and only re-balance the oil layers so O1, O2 are odd. O3 parity is
# unconstrained (it is solved by a linear system, not the sqrt trick; the shipped
# scheme uses O3=14, even).
#
# api.h hand-codes many derived constants as arithmetic literals, so the patcher
# (variant_patches/patch_himq_3.py) recomputes every dependent macro (N, M, V1,
# V2, MM, NN, PKSIZE, PKWID, SKSIZE, alp, bet, gam, gam1, eps, epswid, sksize)
# from the four primary knobs and regenerates api.h. The field q=256 is left
# fixed (hardwired in gf256.c).
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent. The weakened source is repacked into the SAME archive name so
# build_cli.sh stays pristine; the committed original archive is never modified.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="HiMQ_3.zip"
# api.h relative to the archive's top-level directory:
API_REL="HiMQ-3/Reference_Implementation/HiMQ-3/api.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_himq_3.py"

# band | folder-encoding | "V O1 O2 O3"
VARIANTS=(
  "easy|n20m12|8 3 3 6"
  "medium|n29m17|12 5 5 7"
  "hard|n41m24|17 9 9 6"
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

  python3 "$PATCHER" "$TMP/$API_REL" $PARAMS

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
