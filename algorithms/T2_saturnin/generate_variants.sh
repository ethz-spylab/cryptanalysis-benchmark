#!/bin/bash
# Saturnin scaling-down variants (Approach A: reduce SATURNIN_CASCADE_R).
#
# encrypt.c declares `#define SATURNIN_CASCADE_R 10`, consumed by every
# saturnin_block_encrypt / _decrypt call in the Cascade construction.
# CTR_R is left at upstream (10) per the spec text.
#
# Medium variant: SATURNIN_CASCADE_R=4 PLUS the last super-round halved.
# The "halved" surgery is applied to saturnin.c: in saturnin_block_encrypt,
# the last loop iteration (i == R-1) performs only S_box + MDS + S_box,
# skipping the SR / second MDS / SR_inv / round-constant / key XOR. Decrypt
# mirrors with S_box_inv + MDS_inv + S_box_inv on its first iteration (which
# corresponds to encrypt's last super-round).
# Recipe: variant_workfolder/final_fixes_recommendation.md (Saturnin entry).
#
# Concealment design: the weakening edit is applied at GENERATION time to the
# extracted upstream source, which is then repacked into the SAME archive name.
# build_cli.sh therefore stays byte-identical to base, and no patch artifact
# ever lands under environment/ (the committed patcher lives in the
# algorithm-root variant_patches/, outside the Docker build context).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"

SRC_REL="environment/algorithm_src"
ARCHIVE="saturnin.zip"
# ref dir inside the archive (where encrypt.c / saturnin.c live)
REF_REL="saturnin/Implementations/crypto_aead/saturninctrcascadev2/ref"

# suffix | cascade_r | halflast (1=yes, 0=no)
VARIANTS=(
    "hard_r4|4|0"
    "medium_r4_halflast|4|1"
    "easy_r3|3|0"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r SUFFIX R HALFLAST <<< "$entry"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    python3 "$SCRIPT_DIR/variant_patches/patch_saturnin.py" \
        "$TMP/$REF_REL" "$R" "$HALFLAST"

    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    chmod -R u+w "$TMP" 2>/dev/null || true
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
