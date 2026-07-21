#!/bin/bash
# Approach A (reduce ring dimension N) per algorithm_scaling_down/nist_pqc/ding_key_exchange.txt
#   Hard   N=448  (beta ~235) -> core-SVP ~2^65
#   Medium N=352  (beta ~160) -> core-SVP ~2^47
#   Easy   N=288  (beta ~117) -> core-SVP ~2^34
# Shipped full-strength default: #define N 512 (beta ~269, ~2^78 core-SVP).
#
# Ding Key Exchange is a Ring-LWE KEM in R_q = Z_q[x]/(x^N + 1). Lattice-attack
# cost is governed by the BKZ block size beta required at dimension N for the
# fixed q/sigma, so N is the single monotone weakening knob. q (120833) and
# sigma (4.19) are held fixed; correctness is per-coordinate and essentially
# independent of N, so smaller N still round-trips. The patcher edits N in
# api.h (key/ciphertext byte sizes are all defined in terms of N, so they
# update automatically) and relaxes kem.c's `#if N == 512` CDT-table guard and
# its two runtime `if(n == 512)` sigma-selection guards to `<= 512`, keeping the
# correct sigma_se_512 tables/width live for any smaller N (see patch_ding.py).
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enters the Docker build context => invisible to the
# agent). The weakened source is repacked into the same Ding_LWE_Key_Exchange.zip
# archive name so build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Ding_LWE_Key_Exchange.zip"
# Ding_LWE_Key_Exchange.zip extracts its dirs (KAT/, Reference_Implementation/, ...)
# directly at the archive root (no single top-level dir), so the patch target is
# resolved relative to the unzip root.
TARGET_REL="Reference_Implementation"            # dir holding api.h / kem.c

# band|N
VARIANTS=(
  "easy|288"
  "medium|352"
  "hard|448"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND NVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_n${NVAL}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_ding.py" \
          "$TMP/$TARGET_REL" "$NVAL"
  # Repack with the same internal layout build_cli.sh expects (dirs at root).
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Remove patch artifacts from the variant so nothing leaks into the task.
  rm -rf "$VARIANT_DIR/variant_patches"
done
