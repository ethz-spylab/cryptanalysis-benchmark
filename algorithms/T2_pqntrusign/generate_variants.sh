#!/bin/bash
# Scaling-down variants for pqNTRUsign (Gaussian-1024), per
# algorithm_scaling_down/nist_pqc/pqntrusign.txt.
#
# Approach A: reduce the NTRU ring degree N (the primary security parameter;
# core-SVP cost ~ 2^(0.292*beta) with beta ~ 0.43*N for fixed q=65537/noise).
# The reference NTT is a naive O(N^2) evaluation at the N roots of x^N+1 mod q,
# so the precomputed roots/invntt tables, inv_N, the struct fields (N, N_bits,
# padded_N) and the hardcoded key/signature byte sizes in api.h must all be
# regenerated for the new degree. variant_patches/patch_pqntrusign.py does this.
#
#   Hard   N=512  d=205  beta~220  core-SVP ~2^64
#   Easy   N=256  d=51   beta~110  core-SVP ~2^32
#
# Medium N=384 d=77  beta~165  core-SVP ~2^48
#
# Medium (N=384) is NOT a power of two: q=65537 = 2^16+1 admits a negacyclic
# NTT only when 2N | 2^16, i.e. only for power-of-two N, and 768 does not
# divide 2^16. There is no power of two between 256 and 512. Rather than change
# q (which would cascade into the rejection-sampling bounds B_s/B_t/norm_bound_*),
# the medium band keeps q=65537 unchanged and only swaps the keygen ring
# DIVISION away from the NTT: the reference NTT is used solely in keygen to
# compute h = g/(p*f) mod (x^N+1, q); the sign/verify ring MULTIPLIES already
# use the schoolbook/Karatsuba path (pol_mul_coefficients / pol_mul_mod_p),
# which works for any N. variant_patches/patch_pqntrusign_medium.py therefore
# replaces only the keygen division with a schoolbook negacyclic ring division
# (Gaussian elimination mod q, q prime => field). Because q is unchanged every
# signature/rejection bound stays valid. d is scaled to 77 (= round(205*384/1024),
# matching the original secret-key density d/N ~ 0.2 and satisfying 2d+1 <= N),
# reflected in the folder name (..._n384d77).
#
# Note on d (product-form +/-1 weight): pol_gen_flat() needs 2*d+1 nonzero
# coefficients to fit in N. The shipped d=205 (411 nonzeros) fits N=512 but
# NOT N=256, where keygen would loop forever. For the Easy band d is scaled
# proportionally to 51 (= round(205*256/1024)), keeping the secret-key density
# d/N ~ 0.2 of the original. Sparser/shorter (f,g) can only make the lattice
# easier, consistent with the "easy" label. This deviation is recorded in the
# folder name (..._n256d51).
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enter the Docker build context => invisible to the
# agent). The weakened source is repacked into the same archive name so
# build_cli.sh stays pristine. The committed vendored archive is NEVER touched
# (we always repack into $VARIANT_DIR, never $SCRIPT_DIR).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="pqNTRUsign.zip"
EXTRACT_ROOT="pqNTRUsign"           # top-level dir inside the archive
REF_REL="Reference_Implementation"  # patcher operates on this subtree
# Easy/hard reduce N via the NTT-regenerating patcher; medium (non-power-of-two
# N) uses the schoolbook-ring-division patcher instead (see header above).
PATCHER="$SCRIPT_DIR/variant_patches/patch_pqntrusign.py"
PATCHER_MEDIUM="$SCRIPT_DIR/variant_patches/patch_pqntrusign_medium.py"

# band|param-encoding|N|d|patcher
VARIANTS=(
  "easy|n256d51|256|51|$PATCHER"
  "medium|n384d77|384|77|$PATCHER_MEDIUM"
  "hard|n512|512|205|$PATCHER"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC N D VARIANT_PATCHER <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$VARIANT_PATCHER" "$TMP/$EXTRACT_ROOT/$REF_REL" "$N" "$D"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done
