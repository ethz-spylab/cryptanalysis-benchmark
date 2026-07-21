#!/bin/bash
# Round-reduced variants of FROG (FROGC-2, AES candidate, block cipher).
#
# Knob: FROG iteration/round count
#   AES.H  ->  #define numIter 8   (full strength = 8)
# This single #define drives the ENTIRE cipher: the internal key type is
# `tInternalKey[numIter]`, the key schedule (makeInternalKey / hashKey) sizes and
# fills exactly numIter iteration keys from `sizeof(tInternalKey)`, and both
# encryptFrog and decryptFrog loop `for (iteration = 0; iteration < numIter; ..)`.
# Reducing it keeps encrypt/decrypt round-trip consistent (internal structure is
# regenerated per numIter) while weakening the cipher: round-reduced FROG becomes
# differentially/linearly weak for most keys, and the weakness broadens as the
# iteration count drops. Each band is strictly weaker than the shipped full=8 task.
#   Hard   numIter = 4
#   Medium numIter = 3
#   Easy   numIter = 2
#
# (T1->T2 reclassification: bands are DERIVED from source, not from a proposal,
# so the per-band security levels are approximate; the ordering hard>medium>easy
# and "every band strictly weaker than base numIter=8" hold by construction.)
#
# Patch artifact lives in ./variant_patches/ (algorithm ROOT, outside
# environment/ => never enters the Docker build context => invisible to the
# agent). The weakened source is repacked into the vendored archive (same name)
# so build_cli.sh stays pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"        # algorithm root
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="FROGC-2.zip"
# The archive stores its files at the top level (no wrapping directory), so the
# patch target and repack root are the extraction dir itself.
PATCHER="$SCRIPT_DIR/variant_patches/patch_frog.py"

# band|param-encoding|numIter
VARIANTS=(
    "easy|i2|2"
    "medium|i3|3"
    "hard|i4|4"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r BAND ENC NUMITER <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${BAND}_${ENC}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f  "$VARIANT_DIR/generate_variants.sh"

    # Reset the solution to a placeholder: variants are challenge tasks with no
    # reference solution (matches the T2 rank-metric / KEM variant convention).
    rm -rf "$VARIANT_DIR/solution"
    mkdir -p "$VARIANT_DIR/solution"
    printf 'TODO: no reference solution for this generated variant.\n' \
        > "$VARIANT_DIR/solution/TODO.md"

    # Apply the weakening to the extracted source, then repack into the SAME
    # archive name so build_cli.sh's unzip step is unchanged.
    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"
    python3 "$PATCHER" "$TMP/AES.H" "$NUMITER"
    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    # The patch artifacts sit at the variant root (outside environment/), so
    # they never enter the image; remove them to keep the task folder clean.
    rm -rf "$VARIANT_DIR/variant_patches"
done
