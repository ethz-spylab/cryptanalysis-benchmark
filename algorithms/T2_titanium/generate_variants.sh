#!/bin/bash
# Scaling-down variants for Titanium_CCA_std (NIST PQC round 1, MP-LWE KEM).
#
# Approach (per algorithm_scaling_down/nist_pqc/titanium.txt): reduce the MP-LWE
# degree N. The proposal notes Titanium's NTT layer is the real obstacle: the two
# N-dependent exact transforms have lengths L_NK = N+K+1 and L_NDK = N+D+K+1 that
# must BOTH divide Q-1, which is impossible for any reduced N at the shipped fixed
# Q=118273. We therefore free Q: for each band we pick a reduced N and a new PRIME
# modulus Q' with 768|Q'-1, (N+K+1)|Q'-1 and (N+D+K+1)|Q'-1, kept inside
# (2^16, 2^17) so Q_BITS stays 17 and the unrolled 17-bit packing / Q_BITS-derived
# api.h sizes stay valid. K and D are held fixed; only N and Q' move per band.
# All omega twiddle tables are regenerated as roots of unity mod Q' for the new
# transform lengths (the generator is validated to reproduce the shipped
# N=1024/Q=118273 tables byte-for-byte before any variant is emitted).
#
# Concealment: the patch helper lives in ./variant_patches/ at the algorithm ROOT
# (a sibling of environment/, never in the Docker build context). The weakened
# source is repacked into the SAME archive name so build_cli.sh stays pristine and
# the committed original Titanium.zip is never touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="Titanium.zip"
EXTRACT_SUBDIR="Titanium/Reference_Implementation/Titanium_CCA_std"
PATCHER="$SCRIPT_DIR/variant_patches/patch_titanium.py"

# Gate: the table generator MUST reproduce the shipped (N=1024, Q=118273) tables
# byte-for-byte, otherwise abort before emitting anything.
GATE_TMP="$(mktemp -d)"
unzip -q -o "$SCRIPT_DIR/$SRC_REL/$ARCHIVE" "$EXTRACT_SUBDIR/ntt.c" -d "$GATE_TMP"
python3 - "$PATCHER" "$GATE_TMP/$EXTRACT_SUBDIR/ntt.c" <<'PY'
import sys, re, importlib.util
patcher_path, shipped_ntt = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("pt", patcher_path)
pt = importlib.util.module_from_spec(spec); spec.loader.exec_module(pt)
src = open(shipped_ntt).read()
def tab(name):
    m = re.search(r'%s\[(\d+)\]=\{([^}]*)\}' % name, src)
    return [int(x) for x in m.group(2).split(',')]
Q = 118273
# shipped tables were generated with primitive root gamma0=3128
fwd_dk, inv_dk = pt.gen_table(768, Q, 3128)
fwd_nk, inv_nk = pt.gen_table(1536, Q, 3128)
fwd_ndk, _     = pt.gen_table(1792, Q, 3128)
ok = (fwd_dk == tab('omega_768') and inv_dk == tab('omega_768_inv') and
      fwd_nk == tab('omega_1536') and inv_nk == tab('omega_1536_inv') and
      fwd_ndk == tab('omega_1792') and
      pow(768, -1, Q) == 118119 and pow(1536, -1, Q) == 118196 and
      pow(1792, -1, Q) == 118207)
if not ok:
    sys.exit("FATAL: omega-table generator does NOT reproduce shipped tables")
print("[gate] omega-table generator reproduces shipped tables byte-for-byte: OK")
PY
rm -rf "$GATE_TMP"

# band | N | Q' | folder-encoding
VARIANTS=(
  "easy|256|119809|n256q119809"
  "medium|384|96769|n384q96769"
  "hard|576|91393|n576q91393"
)

for entry in "${VARIANTS[@]}"; do
  IFS='|' read -r BAND N QP ENC <<< "$entry"
  VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"
  echo "[generate] $VARIANT_DIR  (N=$N Q'=$QP)"
  rm -rf "$VARIANT_DIR"
  cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
  rm -f "$VARIANT_DIR/generate_variants.sh"

  ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
  TMP="$(mktemp -d)"
  unzip -q -o "$ARCH" -d "$TMP"
  python3 "$PATCHER" "$TMP/$EXTRACT_SUBDIR" "$N" "$QP"
  ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
  rm -rf "$TMP"

  rm -rf "$VARIANT_DIR/variant_patches"
done

echo "[generate] done."
