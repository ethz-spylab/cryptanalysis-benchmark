#!/bin/bash
# Scaling-down variants for RankSign (rank-metric, augmented-LRPC signature) per
# algorithm_scaling_down/nist_pqc/ranksign.txt.
#
# Approach: reduce the extension degree PARAM_M together with the code
# parameters, shrinking the Debris-Alazard-Tillich MinRank / Groebner key-recovery
# system. RankSign is only T2 because that MinRank is blocked by the GF(2^32)
# tooling wall (no fast FOSS Groebner over GF(2^32)); making (m,n,k) smaller both
# lowers the algebraic-system size AND makes even slow GF(2^32) linear algebra
# tractable at the easy end. The base field GF(2^32) is kept (reuses the prebuilt
# libmpfq_2_32.a, no mpfq regeneration).
#
# The reference scheme's decoder pins the parameters to a tight family. From the
# code (crypto_sign_keypair / crypto_sign in ranksign.c):
#   * keygen indexes AH[i*PARAM_D + k] with AH of PARAM_N rows  => PARAM_D*(PARAM_N-PARAM_K) <= PARAM_N,
#     i.e. with PARAM_D=2 fixed:  PARAM_N = 2*PARAM_K.
#   * the generalized-erasure LRPC decoder has syndrome-support dim sigma = 2*PARAM_R2
#     and recovers the exact error support only when 2*sigma <= PARAM_M + PARAM_R2,
#     i.e.  PARAM_M >= 3*PARAM_R2, together with PARAM_K = PARAM_D*(PARAM_R2 - PARAM_T).
#   * the signature support is E (+) T2, so  PARAM_R = PARAM_R2 + PARAM_T2  (PARAM_T2=1).
# The shipped RankSign-I set (m=21,n=20,k=10,t=2,r2=7,r=8) sits exactly on these
# equalities. Each band keeps PARAM_M=3*PARAM_R2, PARAM_N=2*PARAM_K,
# PARAM_K=PARAM_D*(PARAM_R2-PARAM_T), PARAM_R=PARAM_R2+PARAM_T2 -- a uniform,
# verified-round-tripping shrink of the whole family (NOT emitting the shipped
# full-strength set).
#
# FORGERY-SECURITY MARGIN (fixed 2026-07-07). Verification accepts a length-(n+t)
# signature iff Hpub*sig == syndrome(H(m)) over the first n-k coords AND rank(sig)
# <= PARAM_R. With Hpub in systematic form [I_{n-k}|A], an attacker can place the
# n-k syndrome elements in the identity block and zero the rest, yielding a vector
# of rank <= n-k that satisfies the syndrome with NO trapdoor/decoding work. That
# forgery is rejected only when  n-k > PARAM_R,  i.e. margin  m0 := (n-k) - r >= 1;
# otherwise rank-syndrome-decoding is trivial and SignatureForgeryGame is won with
# zero cryptanalysis (this is what happened in crypto-debug-mythos5-june07).
# With n-k = PARAM_N-PARAM_K = PARAM_K = PARAM_D*(PARAM_R2-PARAM_T) and
# r = PARAM_R2+PARAM_T2, the margin is  m0 = PARAM_D*(PARAM_R2-PARAM_T) - PARAM_R2
# - PARAM_T2.  The ORIGINAL recipe used PARAM_T=2, giving m0 = PARAM_R2 - 5, which
# is NEGATIVE for easy (r2=4 -> -1) and ZERO for medium (r2=5 -> 0): both were
# vacuously/trivially forgeable. There is no PARAM_T=2 choice that keeps m0>=1 for
# a sub-baseline band (it needs r2>=6=baseline), so we set PARAM_T=1: then
# m0 = PARAM_R2 - 3 >= 1 for every band, PARAM_K=PARAM_D*(PARAM_R2-1)=2*(r2-1), and
# the decoder equality PARAM_K=PARAM_D*(PARAM_R2-PARAM_T) still holds so honest
# sign->verify round-trips (validated 5/5 per band at build time). Baseline
# RankSign-I already has m0=2 and is untouched.
#
# NOTE: because RankSign is broken by MinRank/Groebner KEY RECOVERY (the intended
# T2 attack, feasible from the small (m,n,k)), reducing PARAM_T only removes the
# NON-cryptanalytic forgery shortcut; it does not affect that intended attack. The
# (n,k) grew vs the original recipe (the intended MinRank cost should be re-checked
# against the target easy/medium/hard bands).
#
#   Baseline (RankSign-I, hardest, NOT a variant): m=21 n=20 k=10 t=2 r2=7 r=8  (m0=2)
#   Hard    m=18 n=20 k=10 t=1 r2=6 r=7  (m0=3)
#   Medium  m=15 n=16 k=8  t=1 r2=5 r=6  (m0=2)
#   Easy    m=12 n=12 k=6  t=1 r2=4 r=5  (m0=1)
#
# Because PARAM_M changes, a fresh irreducible degree-PARAM_M modulus over
# GF(2^32) is installed per band (the shipped modulus is hardwired to degree 21 in
# ffi/ffi_elt.c::generateExtension). The COEFFS lists below are monic degree-M
# irreducibles over GF(2^32)=GF(2)[t]/(t^32+t^7+t^3+t^2+1), coefficients low degree
# first, each an mpfq_2_32 element as a 32-bit int (bit i = t^i) -- verified
# irreducible in Sage. The patcher also recomputes api.h's CRYPTO_*BYTES from the
# new parameters.
#
# Patch artifact (variant_patches/patch_ranksign.py) lives at the algorithm ROOT
# (a sibling of environment/), so it never enters the Docker build context and is
# invisible to the agent. The weakened source is repacked into the SAME archive
# name inside the variant copy, so build_cli.sh and the committed original archive
# stay byte-identical.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="RankSign.zip"
# build_cli.sh compiles RankSign/Reference_Implementation/RankSign-I.
REF_SRC="RankSign/Reference_Implementation/RankSign-I/src"

IRR18="1831814839,2371920754,3235249089,3190129303,722329719,584065212,1480224791,1065878360,2530639045,325931914,242511606,4104214102,1284739679,2240103433,4040538654,1695576711,993432201,1920028143,1"
IRR15="600938037,1704031783,2413450858,3124647275,2465546021,2085647638,3376826923,1373881800,1127485533,2308038445,1276140486,2448720932,358608769,124375445,1932545408,1"
IRR12="384442179,3387698346,3668101751,1933932550,58259112,1184685222,249742768,1167451407,169062095,3586668611,3310104305,31386701,1"

# band|param-encoding|M|N|K|T|R|R2|COEFFS
# PARAM_T=1 (was 2) so the forgery-security margin (n-k)-r >= 1 in every band
# (see the FORGERY-SECURITY MARGIN note above). N=2K=2*D*(R2-1), M=3*R2 unchanged.
VARIANTS=(
  "easy|m12n12|12|12|6|1|5|4|$IRR12"
  "medium|m15n16|15|16|8|1|6|5|$IRR15"
  "hard|m18n20|18|20|10|1|7|6|$IRR18"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND ENC M N K T R R2 COEFFS <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f  "$VARIANT_DIR/generate_variants.sh"

  # These are challenge tasks. Reset the inherited solution/ (the base's
  # non-winning full-strength DAT partial: solve.sh + NOTES.md + lib/, written
  # for the GF(2^32) full parameters and inapplicable to the reduced variant)
  # to a clean TODO placeholder, matching the other T2 rank-metric variants
  # (T2_rqc / T2_ouroboros_r ship solution/TODO.md).
  rm -rf "$VARIANT_DIR/solution"
  mkdir -p "$VARIANT_DIR/solution"
  cat > "$VARIANT_DIR/solution/TODO.md" <<'TODO_EOF'
This folder should contain a script `solve.sh` containing an example of how your algorithm can be broken. The implementation should follow the specification of the [harbor framework](https://harborframework.com/docs/task-format#solution-optional).

Ideally, this example adheres to the security game framework of this repository. This means that the script should create:
- A file `/app/security_game_choice.txt` containing a single string denoting the security game that is being won by this solution (for example SymmetricTargetKeyRecoveryGame).
- A file `/app/attack.sh` containing the actual attack. **Note**: This attack should play (and win) the security game specified in `/app/security_game_choice.txt`. For this, it can interact with the game server using the provided client (see `security_game_framework/environment/client/game_controller_client.py`). Note that the security game specified in `/app/security_game_choice.txt` will be automatically started, and should not be restarted again by your attack.

See https://harborframework.com/docs/task-format#solution-optional
and https://harborframework.com/docs/task-tutorial for more information.
TODO_EOF

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$SCRIPT_DIR/variant_patches/patch_ranksign.py" \
      "$TMP/$REF_SRC" "$M" "$N" "$K" "$T" "$R" "$R2" "$COEFFS"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  # Never ship the patch artifacts inside a task (concealment).
  rm -rf "$VARIANT_DIR/variant_patches"
done
