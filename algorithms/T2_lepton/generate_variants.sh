#!/bin/bash
# Scaling-down variants for Lepton (Light-I, LPN-based CCA KEM, NIST PQC round-1).
#
# No algorithm_scaling_down/ proposal exists for Lepton, so the knob + bands are
# DERIVED from source (same situation as the Part-3 T1->T2 reclassified bases).
#
# KNOB: params.h `#define PARAM_K` (LIGHT_I block) -- the Ring-LPN noise/secret
# Hamming weight. Lepton's public key is b = a*s + e with s,e each weight PARAM_K
# over GF(2)[X]/(X^N+X^M+1) (N=8100, M=9). Recovering s is decoding a weight-2*PARAM_K
# error in the length-2N code [A | I] via information-set decoding (quasi-cyclic
# DOOM-Prange). The full-strength set PARAM_K=16 (target weight 32) is NOT reliably
# in-budget (mean ~700 s on 8 cores, fat exponential tail) -- it stays the unsolved
# T2 challenge. Lowering PARAM_K shrinks the ISD target weight; empirically the
# 8-core recovery mean scales ~= 8 s * 1.74^(PARAM_K-8) (so K=16 -> ~700 s), giving a
# monotone, tight-variance family. Everything else derives from PARAM_K via existing
# macros (CPA_SK_BYTES=2*PARAM_K, PARAM_3K=3*PARAM_K, poly_noise=uint16_t[PARAM_K]),
# so a single one-line edit fully and self-consistently weakens the scheme; N/M/RCN
# and the BCH/repetition decoder are unchanged and round-trip cleanly (lower noise =>
# equal-or-lower decode-failure rate).
#
#   Baseline (Light-I, hardest, NOT a variant): PARAM_K=16  (mean ~700 s, T2 challenge)
#   Hard    PARAM_K=12   (2*K=24; mean ~70-130 s)
#   Medium  PARAM_K=10   (2*K=20; mean ~25-50 s)
#   Easy    PARAM_K=8    (2*K=16; mean ~6-13 s)
#
# Each variant ships a WORKING solution/ (solve.sh + parameterized leptsolve.c that
# recovers s and computes the shared secret, targeting KEMSharedSecretRecoveryGame).
#
# Concealment (per the variant playbook): the patch artifact lives at the algorithm
# ROOT variant_patches/ (a sibling of environment/, so it never enters the Docker
# build context and is invisible to the agent). The weakened source is repacked into
# the SAME archive name inside the variant copy, so build_cli.sh and the committed
# original archive stay byte-identical.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Lepton.zip"
# build_cli.sh copies Lepton/Reference_Implementation/*.{c,h}; params.h lives here.
REF_SRC="Lepton/Reference_Implementation"

# band|param-encoding|PARAM_K
VARIANTS=(
  "easy|k8|8"
  "medium|k10|10"
  "hard|k12|12"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC K <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  # Repack the weakened archive INSIDE the variant copy (never touch the committed
  # original archive under $SCRIPT_DIR).
  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_lepton.py" "$TMP/$REF_SRC" "$K"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Ship the WORKING solution (solve.sh + parameterized leptsolve.c) for this variant,
  # replacing the base's TODO.md placeholder.
  rm -rf "$VARIANT_DIR/solution"
  mkdir -p "$VARIANT_DIR/solution"
  cp "$SCRIPT_DIR/variant_patches/solution/solve.sh" "$VARIANT_DIR/solution/solve.sh"
  cp "$SCRIPT_DIR/variant_patches/solution/leptsolve.c" "$VARIANT_DIR/solution/leptsolve.c"
  chmod +x "$VARIANT_DIR/solution/solve.sh"

  # Never ship the patch artifacts inside a task (concealment).
  rm -rf "$VARIANT_DIR/variant_patches"
done
