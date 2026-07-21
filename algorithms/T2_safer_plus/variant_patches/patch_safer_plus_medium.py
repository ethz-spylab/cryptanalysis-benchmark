#!/usr/bin/env python3
"""SAFER+ medium variant patch.

Truncates the unrolled `encrypt()` / `decrypt()` round chains to R=3 and
appends a single linear PHT layer in `encrypt()` (mirrored as an inverse
PHT layer at the head of `decrypt()`'s round chain) per the recipe in
`variant_workfolder/final_fixes_recommendation.md` (SAFER+ section).

The PHT layer is the 4-stage Pseudo-Hadamard Transform copied verbatim
from `do_fr` (lines 201-235 of the upstream Gladman safer+.c). The
inverse PHT mirrors lines 255-289 of `do_ir`. Because the two blocks are
exact inverses, encrypt/decrypt still compose to the identity.

Usage: python3 patch_safer_plus_medium.py cipher.c
"""

import re
import sys

PHT_BLOCK = """
    /* SAFER+ medium-variant: trailing linear PHT layer (S-box-free). */
    blk[ 1] += blk[ 0]; blk[ 0] += blk[ 1];
    blk[ 3] += blk[ 2]; blk[ 2] += blk[ 3];
    blk[ 5] += blk[ 4]; blk[ 4] += blk[ 5];
    blk[ 7] += blk[ 6]; blk[ 6] += blk[ 7];
    blk[ 9] += blk[ 8]; blk[ 8] += blk[ 9];
    blk[11] += blk[10]; blk[10] += blk[11];
    blk[13] += blk[12]; blk[12] += blk[13];
    blk[15] += blk[14]; blk[14] += blk[15];

    blk[ 7] += blk[ 0]; blk[ 0] += blk[ 7];
    blk[ 1] += blk[ 2]; blk[ 2] += blk[ 1];
    blk[ 3] += blk[ 4]; blk[ 4] += blk[ 3];
    blk[ 5] += blk[ 6]; blk[ 6] += blk[ 5];
    blk[11] += blk[ 8]; blk[ 8] += blk[11];
    blk[ 9] += blk[10]; blk[10] += blk[ 9];
    blk[15] += blk[12]; blk[12] += blk[15];
    blk[13] += blk[14]; blk[14] += blk[13];

    blk[ 3] += blk[ 0]; blk[ 0] += blk[ 3];
    blk[15] += blk[ 2]; blk[ 2] += blk[15];
    blk[ 7] += blk[ 4]; blk[ 4] += blk[ 7];
    blk[ 1] += blk[ 6]; blk[ 6] += blk[ 1];
    blk[ 5] += blk[ 8]; blk[ 8] += blk[ 5];
    blk[13] += blk[10]; blk[10] += blk[13];
    blk[11] += blk[12]; blk[12] += blk[11];
    blk[ 9] += blk[14]; blk[14] += blk[ 9];

    blk[13] += blk[ 0]; blk[ 0] += blk[13];
    blk[ 5] += blk[ 2]; blk[ 2] += blk[ 5];
    blk[ 9] += blk[ 4]; blk[ 4] += blk[ 9];
    blk[11] += blk[ 6]; blk[ 6] += blk[11];
    blk[15] += blk[ 8]; blk[ 8] += blk[15];
    blk[ 1] += blk[10]; blk[10] += blk[ 1];
    blk[ 3] += blk[12]; blk[12] += blk[ 3];
    blk[ 7] += blk[14]; blk[14] += blk[ 7];

"""

IPHT_BLOCK = """
    /* SAFER+ medium-variant: leading inverse linear PHT layer. */
    blk[14] -= blk[ 7]; blk[ 7] -= blk[14];
    blk[12] -= blk[ 3]; blk[ 3] -= blk[12];
    blk[10] -= blk[ 1]; blk[ 1] -= blk[10];
    blk[ 8] -= blk[15]; blk[15] -= blk[ 8];
    blk[ 6] -= blk[11]; blk[11] -= blk[ 6];
    blk[ 4] -= blk[ 9]; blk[ 9] -= blk[ 4];
    blk[ 2] -= blk[ 5]; blk[ 5] -= blk[ 2];
    blk[ 0] -= blk[13]; blk[13] -= blk[ 0];

    blk[14] -= blk[ 9]; blk[ 9] -= blk[14];
    blk[12] -= blk[11]; blk[11] -= blk[12];
    blk[10] -= blk[13]; blk[13] -= blk[10];
    blk[ 8] -= blk[ 5]; blk[ 5] -= blk[ 8];
    blk[ 6] -= blk[ 1]; blk[ 1] -= blk[ 6];
    blk[ 4] -= blk[ 7]; blk[ 7] -= blk[ 4];
    blk[ 2] -= blk[15]; blk[15] -= blk[ 2];
    blk[ 0] -= blk[ 3]; blk[ 3] -= blk[ 0];

    blk[14] -= blk[13]; blk[13] -= blk[14];
    blk[12] -= blk[15]; blk[15] -= blk[12];
    blk[10] -= blk[ 9]; blk[ 9] -= blk[10];
    blk[ 8] -= blk[11]; blk[11] -= blk[ 8];
    blk[ 6] -= blk[ 5]; blk[ 5] -= blk[ 6];
    blk[ 4] -= blk[ 3]; blk[ 3] -= blk[ 4];
    blk[ 2] -= blk[ 1]; blk[ 1] -= blk[ 2];
    blk[ 0] -= blk[ 7]; blk[ 7] -= blk[ 0];

    blk[14] -= blk[15]; blk[15] -= blk[14];
    blk[12] -= blk[13]; blk[13] -= blk[12];
    blk[10] -= blk[11]; blk[11] -= blk[10];
    blk[ 8] -= blk[ 9]; blk[ 9] -= blk[ 8];
    blk[ 6] -= blk[ 7]; blk[ 7] -= blk[ 6];
    blk[ 4] -= blk[ 5]; blk[ 5] -= blk[ 4];
    blk[ 2] -= blk[ 3]; blk[ 3] -= blk[ 2];
    blk[ 0] -= blk[ 1]; blk[ 1] -= blk[ 0];

"""


def main():
    path = sys.argv[1]
    with open(path) as f:
        src = f.read()

    # Step 1: truncate to R=3 (delete trailing do_fr / leading do_ir lines).
    drops = [
        re.compile(r"^.*do_fr\(blk, l_key \+  96\);.*\n", re.MULTILINE),
        re.compile(
            r"^.*do_fr\(blk, l_key \+ 128\); do_fr\(blk, l_key \+ 160\);.*\n",
            re.MULTILINE,
        ),
        re.compile(
            r"^.*do_fr\(blk, l_key \+ 192\); do_fr\(blk, l_key \+ 224\);.*\n",
            re.MULTILINE,
        ),
        re.compile(
            r"^.*do_ir\(blk, l_key \+ 224\); do_ir\(blk, l_key \+ 192\);.*\n",
            re.MULTILINE,
        ),
        re.compile(
            r"^.*do_ir\(blk, l_key \+ 160\); do_ir\(blk, l_key \+ 128\);.*\n",
            re.MULTILINE,
        ),
        re.compile(r"^.*do_ir\(blk, l_key \+  96\);.*\n", re.MULTILINE),
    ]
    # The original source has lines like "do_fr(blk, l_key +  64); do_fr(blk, l_key +  96);"
    # — we first split that line so the +96 portion can be dropped cleanly.
    src = src.replace(
        "do_fr(blk, l_key +  64); do_fr(blk, l_key +  96);",
        "do_fr(blk, l_key +  64);\n    do_fr(blk, l_key +  96);",
    )
    src = src.replace(
        "do_ir(blk, l_key +  96); do_ir(blk, l_key +  64);",
        "do_ir(blk, l_key +  96);\n    do_ir(blk, l_key +  64);",
    )
    for pat in drops:
        src = pat.sub("", src)

    # Step 2: rewrite post-whitening offset to l_key + 96 (= 32*R).
    src = src.replace("kp = l_key + 16 * k_bytes;", "kp = l_key + 96;")

    # Step 3: insert PHT block in encrypt() right before "kp = l_key + 96;".
    # We want only the encrypt() instance, not decrypt(). Encrypt's
    # occurrence is the one preceded by do_fr lines; decrypt's is at the
    # very top of the function. We rely on encrypt being defined first
    # (line ordering preserved) and replace occurrences in order.
    enc_marker = "    kp = l_key + 96;"
    parts = src.split(enc_marker, 2)
    if len(parts) != 3:
        raise SystemExit(
            f"expected exactly 2 occurrences of post-whitening marker, got {len(parts) - 1}"
        )
    src = (
        parts[0]
        + PHT_BLOCK
        + "    "
        + enc_marker.lstrip()
        + parts[1]
        + enc_marker
        + parts[2]
    )

    # Step 4: insert inverse-PHT block in decrypt() right before the first
    # surviving do_ir call (do_ir at offset 64). decrypt has the full
    # post-whitening block then the do_ir chain; we anchor to the leading
    # "do_ir(blk, l_key +  64);" line.
    dec_anchor = "    do_ir(blk, l_key +  64);"
    if src.count(dec_anchor) != 1:
        raise SystemExit(
            f"expected exactly 1 occurrence of decrypt anchor, got {src.count(dec_anchor)}"
        )
    src = src.replace(dec_anchor, IPHT_BLOCK + dec_anchor, 1)

    with open(path, "w") as f:
        f.write(src)


if __name__ == "__main__":
    main()
