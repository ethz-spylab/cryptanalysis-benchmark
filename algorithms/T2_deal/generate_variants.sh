#!/bin/bash
# T1->T2 reclassified DEAL-128 (6-round Feistel, single-DES round function).
# NO proposal file: the knob and band values are DERIVED from the source.
#
# Knob: the DEAL Feistel round count. deal.c UNROLLS the rounds (no #define / no
# loop) as a sequence of `des_ecm(..., l_key + <off>)` calls in encrypt() and
# decrypt(); the CLI always uses the 128-bit key (k_len==2 => 6 rounds). We drop
# whole Feistel rounds (matched encrypt+decrypt reversals) via a python patcher
# so the reduced cipher still round-trips.
#
#   Base (shipped full strength) = 6 rounds  --  NEVER emitted as a variant
#   Hard   = 4 rounds   (variant_hard_r4)
#   Medium = 3 rounds   (variant_medium_r3)
#   Easy   = 2 rounds   (variant_easy_r2)
#
# Monotone: hard(4) > medium(3) > easy(2) in strength, all strictly < base(6).
# Band<->bit-level mapping is best-effort only (see IMPLEMENTATION_NOTES): a
# round-reduced DEAL key recovery reduces to DES-subkey search whose floor is
# ~2^56, so the absolute work factors are approximate; the ordering + strict
# weakening are guaranteed by construction.
#
# Mode: generation-time patch + repack. The patcher lives in ./variant_patches/
# (algorithm ROOT, sibling of environment/, so it never enters the Docker build
# context and is invisible to the agent). The weakened deal.c is repacked into
# the SAME archive name (DEAL-2.zip) inside the VARIANT copy, so build_cli.sh and
# the committed base archive stay byte-identical.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="DEAL-2.zip"
TARGET_FILE="deal.c"   # lives at the top level of DEAL-2.zip (flat archive)

# band|param-encoding|round-count
VARIANTS=(
  "easy|r2|2"
  "medium|r3|3"
  "hard|r4|4"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC ROUNDS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_deal.py" "$TMP/$TARGET_FILE" "$ROUNDS"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Concealment: the patcher must not ship inside the task/Docker context.
  rm -rf "$VARIANT_DIR/variant_patches"

  # Variants are challenge tasks: no reference solution, only a TODO placeholder.
  rm -rf "$VARIANT_DIR/solution"
  mkdir -p "$VARIANT_DIR/solution"
  cat > "$VARIANT_DIR/solution/TODO.md" <<'EOF'
# TODO

No reference solution has been written for this variant yet.
EOF
done
