#!/bin/bash
# Scaling-down variant generator for LEDAkem (code-based QC-LDPC KEM).
# Approach: reduce the circulant block size P (which sets code length N=N0*P)
# together with the intentional error weight NUM_ERRORS_T, in the
# CATEGORY==1 / N0==2 block of
#   Reference_Implementation/KEM/include/qc_ldpc_parameters.h
# per algorithm_scaling_down/nist_pqc/ledakem.txt.
#
#   Hard:   P=15859 t=128   (proposal value; prime, 2 is a primitive root mod P)
#   Medium: P=10909 t=88    (proposal P=10903 fails ord_2(P)=P-1; nearest
#                            qualifying prime 10909 substituted, +6)
#   Easy:   P=7907  t=64    (proposal P=7919 fails ord_2(P)=P-1; nearest
#                            qualifying prime 7907 substituted, -12)
#
# P must be prime AND 2 a primitive root mod P (so x^P-1 = (x-1)*irreducible of
# degree P-1), which the QC-LDPC circulant inversions rely on; the medium/easy
# proposal primes do not satisfy ord_2(P)=P-1, so the nearest qualifying primes
# are used and reflected in the folder names.
#
# The proposal's note that the bit-flip threshold is runtime-computed is wrong:
# bf_decoding.h carries a hardcoded SYNDROME_TRESH_LOOKUP_TABLE keyed on syndrome
# weight (which scales with P/t). patch_ledakem.py therefore also rescales that
# table's weight breakpoints by P/27779 (threshold column kept, it depends only
# on DV/M); without it decapsulation fails for every key at the reduced sizes.
#
# Patch artifacts live in ./variant_patches/ at the algorithm ROOT (a sibling of
# environment/), so they are NEVER part of the Docker build context and stay
# invisible to the agent. The weakened source is repacked into the same archive
# name (LEDAkem.zip) so build_cli.sh remains pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="LEDAkem.zip"
PATCHER="$SCRIPT_DIR/variant_patches/patch_ledakem.py"

# band|folder-encoding|P|NUM_ERRORS_T
VARIANTS=(
  "easy|p7907t64|7907|64"
  "medium|p10909t88|10909|88"
  "hard|p15859t128|15859|128"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC P_VAL T_VAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$PATCHER" "$TMP" "$P_VAL" "$T_VAL"

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
  echo "Generated $VARIANT_DIR (P=$P_VAL NUM_ERRORS_T=$T_VAL)"
done
