#!/bin/bash
# Approach A (reduce GF(2^m) extension degree _m) per algorithm_scaling_down/nist_pqc/mcnie.txt
#   Hard   _m=35  -> ~2^41
#   Medium _m=31  -> ~2^36
#   Easy   _m=29  -> ~2^34
# Shipped full-strength baseline: const short _m = 37 (3Q_128_1, ~2^43 best known).
#
# NOTE (band-lowering exception): the shipped 3Q_128_1 set is already only ~2^43
# against the best (QRCSP/Gaborit structural rank-SD) attack, so the standard
# bands are lowered/compressed to sit strictly below it while preserving
# Hard > Medium > Easy. Every band is a genuine reduction of m below the shipped
# 37 (Hard 35 keeps a ~2-bit margin); the real algorithm stays strictly hardest
# and m=37 is never emitted as a variant.
#
# McNie is a code-based rank-metric PKE/KEM; security rests on Rank Syndrome
# Decoding over GF(2^m). m = `_m` (gf.c) is the single monotone weakening knob:
# the structural attack cost rises ~linearly in the exponent with m. blk=31
# (n=3*blk=93, k=62), LRPC weight d=3 and error rank r=5 are held fixed; LRPC
# correctness needs r*d <= m (=15), so every band (m >= 29) still round-trips.
# Each chosen m has a nonzero base_poly[m] entry (29,31,35 verified in gf.c) —
# the patcher asserts this and that each edit changed exactly one line.
#
# The upstream crypto derives every byte length from _m at runtime, but the CLI's
# I/O contract hardcodes the m=37 ciphertext size in crypt.h's CIPHER_BYTES; since
# encrypt prints the real runtime length and decrypt demands CIPHER_BYTES, the
# patcher also rewrites CIPHER_BYTES to the real per-m length so the round-trip's
# length check passes (pk/sk/MESSAGE_BYTES stay as safe upper bounds — see
# patch_mcnie.py).
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/ => never enters the Docker build context => invisible to the
# agent). The weakened source is repacked into the same McNie.zip archive name so
# build_cli.sh stays pristine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="McNie.zip"
EXTRACT_ROOT="McNie"   # single top-level dir inside the archive
PARAM_REL="Reference_Implementation/encrypt/3Q_128_1"   # holds gf.c (_m) + crypt.h (CIPHER_BYTES)

# band|m
VARIANTS=(
  "easy|29"
  "medium|31"
  "hard|35"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND MVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_m${MVAL}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_mcnie.py" \
          "$TMP/$EXTRACT_ROOT/$PARAM_REL" "$MVAL"
  # Repack with the same internal layout build_cli.sh expects (single McNie/ root).
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Remove patch artifacts from the variant so nothing leaks into the task.
  rm -rf "$VARIANT_DIR/variant_patches"
done
