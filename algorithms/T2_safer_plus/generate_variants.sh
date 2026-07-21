#!/bin/bash
# SAFER+ scaling-down variants (Approach A: reduce ROUNDS).
#
# The Gladman reference (`safer+.c`, copied to cipher.c by build_cli.sh)
# fully unrolls the 8 round calls in encrypt() / decrypt(); there is no
# `#define ROUNDS`. We patch the unrolled call sequence and the
# post-whitening offset `kp = l_key + 16 * k_bytes;` (which becomes
# l_key + 32*R for the truncated version).
#
# The cli uses a 128-bit key (k_bytes=16), so the `k_bytes > 16/24`
# branches in encrypt/decrypt are dead and unmodified.
#
# Per-spec values: hard=4, easy=3 (per-algo .txt wins over the addendum's
# easy=2). Medium=3+PHT (per
# variant_workfolder/final_fixes_recommendation.md, SAFER+ recipe): keep
# R=3 do_fr/do_ir calls but append a single linear PHT layer at the tail
# of encrypt() and the matching inverse PHT at the head of decrypt()'s
# round chain. The added PHT block is byte-permutation-free so its
# inverse exactly cancels in decrypt; the variant remains a valid
# encryption-decryption pair while gaining ~12 bits of differential
# diffusion above plain R=3.
#
# Concealment mechanism (generation-time repack): the weakening edits live
# in ./variant_patches/ (algorithm ROOT, a sibling of environment/ => never
# enters the Docker build context => invisible to the agent). For each band
# we extract the variant's pristine SAFER.zip, normalize line endings the
# same way build_cli.sh does, apply the band's patch to safer+.c, and repack
# into the SAME archive name. build_cli.sh therefore stays byte-identical to
# the base task and nothing weakening-related ships under environment/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
SRC_REL="environment/algorithm_src"
ARCHIVE="SAFER.zip"
TARGET="safer+.c"   # archived at the top level of SAFER.zip (no subdir)

# suffix | kind:artifact
# - patch:<file>  -> apply unified diff with `patch -p1`
# - py:<file>     -> run python patcher with the target file path as argv
#
# Note on the medium suffix: the underscore between "r3" and "pht" is
# intentionally dropped. With "medium_r3_pht" the variant directory name
# has "_" at char 32, and Harbor's 32-char trial-name truncation + "__"
# join produces "___" — invalid per
# https://github.com/distribution/reference image-ref grammar.
VARIANTS=(
    "hard_r4|patch:variant_hard_r4.patch"
    "medium_r3pht|py:patch_safer_plus_medium.py"
    "easy_r3|patch:variant_easy_r3.patch"
)

for entry in "${VARIANTS[@]}"; do
    IFS='|' read -r SUFFIX SPEC <<< "$entry"
    KIND="${SPEC%%:*}"
    ARTIFACT="${SPEC#*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${ALGO_NAME}_variant_${SUFFIX}"

    rm -rf "$VARIANT_DIR"
    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    rm -f "$VARIANT_DIR/generate_variants.sh"

    ARCH="$VARIANT_DIR/$SRC_REL/$ARCHIVE"
    TMP="$(mktemp -d)"
    unzip -q -o "$ARCH" -d "$TMP"

    # Normalize line endings exactly as build_cli.sh does so the patch /
    # python helper context matches; build_cli.sh re-normalizes the repacked
    # source (a harmless no-op on already-clean text).
    sed -i 's/\r$//' "$TMP/$TARGET"
    tr -d '\r' < "$TMP/$TARGET" > "$TMP/$TARGET.tmp" && mv "$TMP/$TARGET.tmp" "$TMP/$TARGET"

    if [ "$KIND" = "py" ]; then
        python3 "$SCRIPT_DIR/variant_patches/$ARTIFACT" "$TMP/$TARGET"
    else
        patch -p1 -d "$TMP" < "$SCRIPT_DIR/variant_patches/$ARTIFACT"
    fi

    ( cd "$TMP" && rm -f "$ARCH" && zip -q -r -X "$ARCH" . )
    rm -rf "$TMP"

    rm -rf "$VARIANT_DIR/variant_patches"
done
