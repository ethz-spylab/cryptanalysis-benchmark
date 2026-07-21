#!/bin/bash
# DAGS scaling-down variant generator (T1 -> T2 reclassification; bands DERIVED).
#
# DAGS (shipped DAG 96 / dags3 parameter set) is a code-based KEM over a dyadic
# Generalised-Srivastava code: an [n=1216, k=512] code over GF(2^6). Encapsulation
# forms c = u*G + e with a fixed-weight error e of Hamming weight n0_w (=176 at
# full strength); recovering the shared secret from a ciphertext is the
# fixed-weight syndrome-decoding / information-set-decoding (ISD) problem on that
# code, whose work factor drops monotonically as n0_w shrinks below its design
# value. Lowering n0_w is therefore a clean, monotone weakening knob for the
# FOSS-reachable message / shared-secret-recovery attack surface.
#
#   Easy   n0_w = 40    (best-effort, weakest ISD instance)
#   Medium n0_w = 80
#   Hard   n0_w = 128   (best-effort, closest to the shipped base)
#
# All three are STRICTLY weaker than the shipped n0_w=176 and monotone. The
# figures are best-effort (no reviewed scaling-down proposal exists for DAGS —
# this is a Part-3 T1->T2 reclassification), but the monotone ordering and
# strictly-weaker-than-base property hold by construction. The purely structural
# key-recovery attacks (Bardet et al.; Barelli-Couvreur) are Magma-bound and
# n0_w-independent, so they are unaffected and sit outside this scaled surface.
#
# Why n0_w is a safe knob: it is read ONLY by encapsulation.c (error injection)
# and decapsulation.c (weight check + error re-derivation), never by key_gen.c.
# Reducing it leaves the dyadic key generation, the GF(2^6) arithmetic tables and
# every derived buffer size untouched, and only makes decoding easier (fewer
# errors than the GS decoder's capacity), so the KEM round-trip stays valid.
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
ARCHIVE="DAGS.zip"
# param.h relative to the archive's top-level directory (build_cli.sh builds
# DAGS/Reference_Implementation/kem/dags3):
PARAM_REL="DAGS/Reference_Implementation/kem/dags3/param.h"
PATCHER="$SCRIPT_DIR/variant_patches/patch_dags.py"

# band | folder-encoding | n0_w value
VARIANTS=(
  "easy|w40|40"
  "medium|w80|80"
  "hard|w128|128"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC WVAL <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"

  python3 "$PATCHER" "$TMP/$PARAM_REL" "$WVAL"

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
