#!/bin/bash
# Rainbow scaling-down variant generator (T1 -> T2 reclassification).
#
# Approach: reduce the multivariate Oil-and-Vinegar layer sizes (v1, o1, o2)
# together while keeping the field GF(16) fixed. Rainbow has n = v1+o1+o2
# variables, m = o1+o2 equations, and two oil layers. The published breaks of
# Rainbow (Beullens' rectangular-MinRank / band-separation key recovery, and
# direct algebraic signature forgery) all get cheaper as the layers shrink, so
# shrinking (v1,o1,o2) below the SL-1 base (32,32,32) is a monotone weakening
# knob. GF(16) is left fixed so the field-arithmetic tables in gf16.h stay valid.
#
#   Easy   (v1,o1,o2) = (8, 6, 6)   -> n=20  m=12  (best-effort ~2^30-2^40)
#   Medium (v1,o1,o2) = (12,10,10)  -> n=32  m=20  (best-effort ~2^40-2^60)
#   Hard   (v1,o1,o2) = (20,16,16)  -> n=52  m=32  (best-effort ~2^60-2^80)
#
# Security anchoring is best-effort: the rectangular-MinRank key-recovery cost
# scales roughly like GF(16)^o2 = 2^(4*o2) up to polynomial factors (o2 = 6/10/16
# -> ~2^24/2^40/2^64), and direct algebraic forgery of m=o1+o2 quadratics grows
# in the same direction, so the three bands are monotone and land near the target
# difficulty windows. All three are STRICTLY weaker than the shipped (32,32,32).
#
# rainbow_config.h derives EVERY dependent size (_V2, _*_BYTE, _PUB_N, _PUB_M,
# _SIGNATURE_BYTE, _PUB_KEY_LEN, and via rainbow_16.h _SEC_KEY_LEN) from the three
# layer macros by C-preprocessor formulas, so the patcher only rewrites _V1/_O1/
# _O2 and the compiler recomputes all key/signature buffer sizes automatically.
# GF(16) requires each layer size be EVEN (2 nibbles/byte); the patcher enforces
# that plus o1,o2>=1 and v1>=o1, and asserts exactly three substitutions.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, a sibling of
# environment/), so they never enter the Docker build context and stay invisible
# to the agent. The weakened source is repacked into the SAME archive name so
# build_cli.sh stays byte-identical; the committed original archive is untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Rainbow.zip"
# rainbow_config.h relative to the archive's top-level directory:
CONFIG_REL="Rainbow/Reference_Implementation/Ia/rainbow_config.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_rainbow.py"

# band | folder-encoding | "v1 o1 o2"
# Encoding is v<v1>o<o1> with the o1==o2 convention (all bands use o1==o2), kept
# short so the full folder name stays <=32 chars and is never truncated by
# Harbor's trial-name join. The authoritative triple lives in the repacked
# rainbow_config.h and in the comments above.
VARIANTS=(
  "easy|v8o6|8 6 6"
  "medium|v12o10|12 10 10"
  "hard|v20o16|20 16 16"
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

  python3 "$PATCHER" "$TMP/$CONFIG_REL" $PARAMS

  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Concealment: strip patch artifacts and keep only a TODO.md solution stub.
  rm -rf "$VARIANT_DIR/variant_patches"
  rm -rf "$VARIANT_DIR/solution"
  mkdir -p "$VARIANT_DIR/solution"
  cat > "$VARIANT_DIR/solution/TODO.md" <<'EOF'
No reference solution has been written for this variant yet.
EOF
done
