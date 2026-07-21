#!/bin/bash
# Variant generator for T2_qc_mdpc_kem (QC-MDPC KEM, NIST PQC Round 1).
#
# Approach A (reduce the circulant block size MDPC_R together with the weights
# MDPC_W / MDPC_T) per algorithm_scaling_down/nist_pqc/qc_mdpc_kem.txt, keeping
# the rate-1/2, N0=2 geometry. The controlling values live in
#   QC-MDPC KEM - Atsushi Yamada/Reference_Implementation/kem/mdpc/internal.h
# which ships inside QC_MDPC_KEM.zip; we extract, patch, and repack the archive
# under the same name so build_cli.sh stays byte-identical.
#
# Deviations from the proposal's nominal values (forced by the reference impl):
#   * R must be PRIME with 2 a primitive root mod R (ord_2(R)=R-1) so x^R-1
#     factors as (x-1)*(irreducible deg R-1). The proposal's 4001/3001 are prime
#     but 2 is NOT primitive; nearest qualifying primes substituted:
#       hard   4001 -> 4003   medium 3001 -> 3011   easy 2099 (already valid)
#   * WI = W/2 must be ODD, otherwise the per-circulant row has even weight,
#     is divisible by (x-1), and keygen's polynomial inversion asserts/fails.
#     The proposal's even WI (medium 28, easy 20) are bumped to the nearest odd:
#       medium W=56(WI=28) -> W=54(WI=27)   easy W=40(WI=20) -> W=38(WI=19)
#       hard W=78 (WI=39, already odd) unchanged.
#   * The bit-flipping decoder thresholds[] array is hard-calibrated for the
#     full-strength WI=137 and must be rescaled for the reduced row weight or
#     decapsulation always fails. Each band ships a schedule scaled to its WI;
#     all three round-trip with 0 decode failures over 100 fresh iterations.
#
# Patch artifact (variant_patches/patch_qc_mdpc_kem.py) lives at the algorithm
# ROOT, outside environment/, so it never enters the Docker build context and is
# invisible to the agent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="QC_MDPC_KEM.zip"
EXTRACT_ROOT="QC-MDPC KEM - Atsushi Yamada"
HDR_REL="Reference_Implementation/kem/mdpc/internal.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_qc_mdpc_kem.py"

# band|encoding|R|W|T|thresholds(comma-sep, 8 values matching WI schedule)
VARIANTS=(
  "easy|r2099w38t38|2099|38|38|13,12,11,11,10,10,10,10"
  "medium|r3011w54t52|3011|54|52|19,17,16,15,15,14,14,14"
  "hard|r4003w78t72|4003|78|72|27,24,23,22,21,21,20,20"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC R W T THS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_ROOT/$HDR_REL" "$R" "$W" "$T" "$THS"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
  echo "Generated $VARIANT_DIR (R=$R W=$W T=$T)"
done
