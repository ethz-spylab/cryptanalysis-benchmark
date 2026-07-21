#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

# Approach A — reduce N per `variant_workfolder/final_fixes_recommendation.md`
# Section 3 (NTRU). The recipe also called for halving q per band, but two
# upstream constraints make the recipe's q values unworkable:
#
#   1. `packq.c::poly_Sq_tobytes` / `poly_Sq_frombytes` are hand-rolled 11-bit
#      packers — `t[0] >> 8`, `(t[1] & 0x1f) << 3`, ..., 8 coefficients into
#      11 bytes — and assume LOGQ = 11 exactly. CRYPTO_*BYTES sizes derive
#      from LOGQ via `(LOGQ*(N-1)+7)/8`, so reducing LOGQ makes the packer
#      and the buffer sizes disagree (decapsulation reads the wrong bits and
#      the IND-CCA failure path triggers on every trial — confirmed empirically).
#   2. `poly_R2_inv_to_Rq_inv` `#error`s out for `NTRU_Q <= 256`, so LOGQ = 8
#      (recipe's easy band) would not even compile.
#
# We keep LOGQ = 11 (Q = 2048) and reduce only N. NTRU-HPS additionally
# requires that both 2 and 3 are primitive roots mod N (else
# Φ_N(X) = (X^N − 1)/(X − 1) is reducible mod 2 or 3 and the inverse
# routines fail). Direct computation in python over primes 100–600 yields
# the candidate set
#   {101, 139, 149, 163, 173, 197, 211, 269, 293, 317, 379, 389, 461, 509,
#    557}.
# Only N ≥ 255 satisfy the second invariant `NTRU_WEIGHT < N`
# (`NTRU_WEIGHT = Q/8 - 2 = 254`), pruning to {269, 293, 317, 379, 389, 461,
# 509, 557}.
#
# Final shipped values:
#   Hard:   N = 509  (= upstream ntruhps2048509, naming-only — its core-SVP
#                     lattice cost ~2^111 sits above the spec's 2^60–2^80
#                     hard band; same precedent as MAGENTA / ECOH / NewHope-512).
#   Medium: N = 389  (rough core-SVP scaling ~2^85 — slightly above medium
#                     band; closest feasible N to recipe's 401).
#   Easy:   N = 269  (rough core-SVP scaling ~2^59 — at top of easy band;
#                     smallest feasible N satisfying both predicates above,
#                     close to recipe's 251).
#
# Implementation. We patch `params.h::NTRU_N` (literal `509`) at generation
# time: the variant's copy of the upstream zip is unpacked, the band patch in
# ./variant_patches/ is applied, and the tree is repacked into the same archive
# name so build_cli.sh stays byte-identical to base. NTRU_WEIGHT, sample-byte
# counts, public/secret/ciphertext byte sizes are all derived from N at compile
# time, and the cli sizes its I/O buffers from those constants — no further
# edits needed. Ring multiplication is schoolbook (no NTT), so no precomputed
# tables to regenerate either.
#
# Patch artifacts live in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never in the Docker build context => invisible to the agent).

SRC_REL="environment/algorithm_src"
ARCHIVE="NTRU-Round3.zip"
EXTRACT_ROOT="NIST-PQ-Submission-NTRU-20201016"   # top-level dir inside the archive

# Format: <band>|<N>|<patch-file ('' = unmodified upstream, no patch)>
A_VARIANTS=(
    "easy|269|variant_easy.patch"
    "medium|389|variant_medium.patch"
    "hard|509|"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND NVAL PATCH <<< "$entry"
    SUFFIX="${BAND}_n${NVAL}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    if [ -n "$PATCH" ]; then
        ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
        TMP="$(mktemp -d)"
        unzip -q -o "$ARCH" -d "$TMP"
        patch -p1 -d "$TMP/$EXTRACT_ROOT" < "$SCRIPT_DIR/variant_patches/$PATCH"
        ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
        chmod -R u+w "$TMP" 2>/dev/null || true
        rm -rf "$TMP"
    fi
    # Hard variant (NVAL=509) = unmodified upstream; archive left as-is.

    rm -rf "$VARIANT_DIR/variant_patches"
done
