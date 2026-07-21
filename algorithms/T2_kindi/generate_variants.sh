#!/bin/bash
# Approach: reduce the effective Module-LWE dimension n_eff = KINDI_KEM_N * KINDI_KEM_L
# of KINDI-256-3-4-2, per algorithm_scaling_down/nist_pqc/kindi.txt.
#   real:   N=256 L=3  -> n_eff=768  (shipped full strength, never emitted)
#   hard:   N=128 L=3  -> n_eff=384  (~2^60-2^80 core-SVP)   [EMITTED]
#   medium: N=256 L=1  -> n_eff=256  (~2^40-2^60 core-SVP)   [EMITTED]
#   easy:   N=64  L=3  -> n_eff=192  (~2^30-2^40 core-SVP)   [EMITTED]
#
# MEDIUM is a true one-line params.h edit (KINDI_KEM_L 3->1): the FFT tables,
# modulus and every L-derived size update automatically and all L-indexed buffers
# are malloc'd dynamically.  Applied via variant_medium.patch.
#
# HARD / EASY lower the ring degree KINDI_KEM_N (128 / 64).  KINDI's FO transform
# embeds a fixed 256-bit security seed s1 (KINDI_KEM_S1SIZE = 256/8) into 256
# coefficients of a degree-N polynomial -- both core.c recover_s1() and
# gen_randomness() index s1 bits over [0, 8*S1SIZE) -- so N<256 reads/writes out of
# bounds at the shipped seed length.  patch_kindi.py therefore ALSO shrinks the
# embedded seed to N bits (KINDI_KEM_S1SIZE = N/8): this deliberately lowers the
# effective seed entropy (the intended weakening of lambda) and makes the seed
# embedding read exactly N coefficients -> in bounds -> keygen/encaps/decaps stay
# end-to-end consistent (the 32-byte shared secret / public seed are unchanged).
# The patcher also regenerates the complex-FFT twiddle tables data_fft/<N>/*.data,
# bitrev<N>.code, and the matching "#if/#elif KINDI_KEM_N == <N>" include branches
# in poly.h and fft_transform.c (the table generators were validated to reproduce
# the shipped 256/512 tables to floating-point precision).  Verified round-trip:
# N=128 and N=64 each 200/200 fresh keygen->encaps->decaps shared-secret matches,
# 0 decapsulation failures (smaller N -> less product noise than the base N=256).
#
# Patch artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent.  The weakened source is repacked into the same KINDI.zip name so
# build_cli.sh stays byte-identical.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="KINDI.zip"

# band|param-encoding|patch-kind|patch-arg
#   patch-kind=diff -> apply unified diff variant_patches/<arg> with patch -p1
#   patch-kind=py   -> run variant_patches/patch_kindi.py <extract-root> <arg=N>
VARIANTS=(
  "hard|n128l3|py|128"
  "medium|n256l1|diff|variant_medium.patch"
  "easy|n64l3|py|64"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC KIND ARG <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  if [ "$KIND" = "diff" ]; then
    patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$ARG"
  else
    python3 "$SCRIPT_DIR/variant_patches/patch_kindi.py" "$TMP" "$ARG"
  fi
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
