#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

# Approach A (reduce p) is not implementable as a sed-level patch. The
# Streamlined NTRU Prime reference impl hard-codes one tuple
# (p, q, w, Rounded_bytes, Rq_bytes) per supported parameter set in
# `params.h` (SIZE761 / SIZE653 / SIZE857 / SIZE953 / SIZE1013 / SIZE1277);
# the smallest is sntrup653 (p=653). The encoder/decoder constants
# (`Rounded_bytes`, `Rq_bytes`) and the API byte sizes
# (CRYPTO_PUBLICKEYBYTES, CRYPTO_SECRETKEYBYTES, CRYPTO_CIPHERTEXTBYTES
# in `crypto_kem.h`) are derived from the (p, q) tuple but committed as
# literal numbers — switching p requires recomputing every one. More
# fundamentally, sntrup needs `x^p − x − 1` irreducible mod q (the
# ring-splitting condition); the spec's targets (hard p=269, addendum
# medium p=191, easy p=137) are not in the upstream's tested set, so
# picking a matching q and verifying irreducibility is required, well
# beyond a sed patch.
#
# Per the MAGENTA / ECOH / CRYPTON / ARIRANG precedent, we ship only
# the **hard** variant equal to the unmodified upstream sntrup653
# (p = 653, q = 4621, w = 288). Note that p = 653 sits *above* the
# spec's hard band (cryptanalysis section: core-SVP ~2^137), so the
# "hard" label here is naming-only.

A_VARIANTS=(
    "hard|653"
)

for entry in "${A_VARIANTS[@]}"; do
    IFS='|' read -r BAND P <<< "$entry"
    SUFFIX="${BAND}_p${P}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # No build patch — hard variant equals unmodified upstream build
    # (build_cli.sh selects sntrup653).
done
