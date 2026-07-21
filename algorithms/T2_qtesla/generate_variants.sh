#!/bin/bash
# Approach A (reduce the ring dimension PARAM_N) per
#   algorithm_scaling_down/nist_pqc/qtesla.txt
#   Hard    PARAM_N=256 (N_LOG=8)  q=4205569   unchanged    ~2^60-2^80
#   Medium  PARAM_N=256 (N_LOG=8)  q=67104769 (~2^26 prime) ~2^40-2^60
#   Easy    PARAM_N=128 (N_LOG=7)  q=4205569   unchanged    ~2^30-2^40
#
# MEDIUM BAND: the proposal realises Medium at n=256 with q raised to an
# NTT-friendly prime ~2^26 (q must stay prime and q == 1 mod 2n; n is power-of-two
# quantized, so n=192 is unavailable and the q-bridge is the only route to the
# 2^40-2^60 band).  q=67104769 is prime, 67104769 == 1 mod 512 (=2n), and just
# under 2^26.  Raising q is correctness-safe (it only loosens the rejection /
# decoding bounds) but the -D_qTESLA_I_ build path (which build_cli.sh MUST keep)
# accumulates the forward/inverse NTT butterflies UNREDUCED in the int32 `poly`
# storage; the measured worst-case peak is ~145*q at n=256, so q~2^26 overflows
# int32 and poly_mul produces garbage.  The Medium patch therefore ALSO widens
# poly.c (4th patcher arg "widen"): it enables qTESLA's own barr_reduce for the I
# build and inserts it after every butterfly add/sub in ntt()/nttinv(), exactly
# as the larger-q qTESLA III/V sets do, so coefficients stay reduced mod q
# (|coeff| < ~2q < 2^27) at every stage.  Barrett reduction is value-preserving
# mod q and the NTT is linear mod q, so the result is bit-identical (mod q) to an
# overflow-free reference -- only intermediate magnitudes change.  Easy/hard pass
# no 4th arg and poly.c is left pristine.
#
# Reducing PARAM_N is explicitly NOT a one-line change: the patcher
# variant_patches/patch_qtesla.py updates PARAM_N_LOG, recomputes the Montgomery
# normaliser PARAM_R2_INVN, and REGENERATES the size-n negacyclic-NTT twiddle
# tables (zeta/zetainv) in consts.c as the 2n-th roots of unity mod q in the exact
# index ordering poly.c's ntt()/nttinv() consume (the generation formula was
# verified byte-identical against the shipped n=512 tables).  gauss.h's CHUNK_SIZE
# is also lowered to n so the Gaussian sampler does not overflow poly z[PARAM_N].
#
# Patch artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they are OUTSIDE the Docker build context => invisible to the
# agent. The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="qTESLA-Round2.zip"
EXTRACT_ROOT="NIST_submission_round2_Mar2019"
REF_REL="Reference_implementation/qTesla_I"
PATCHER="$SCRIPT_DIR/variant_patches/patch_qtesla.py"

# band|param-encoding|PARAM_N|PARAM_Q|WIDEN
# WIDEN=1 ports the III/V Barrett reduction into the I-path NTT so the larger
# Medium modulus q~2^26 cannot overflow the int32 poly accumulators (see note).
VARIANTS=(
  "easy|n128|128|4205569|0"
  "medium|n256_q67104769|256|67104769|1"
  "hard|n256|256|4205569|0"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC PARAM_N PARAM_Q WIDEN <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$REF_REL" "$PARAM_N" "$PARAM_Q" "$WIDEN"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
