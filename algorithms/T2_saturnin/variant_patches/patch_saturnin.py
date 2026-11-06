#!/usr/bin/env python3
"""Saturnin scaling-down patcher (generation-time, applied to the extracted
reference tree before repack).

Usage:
    patch_saturnin.py <ref_dir> <cascade_r> <halflast>

<ref_dir>   directory holding encrypt.c / saturnin.c (the upstream
            saturninctrcascadev2/ref folder).
<cascade_r> integer value for SATURNIN_CASCADE_R in encrypt.c.
<halflast>  "1" to additionally halve the last super-round in saturnin.c,
            "0" to leave saturnin.c untouched.

Both edits assert they changed exactly one location and fail loudly otherwise,
so a generator running under `set -e` aborts rather than emit an unweakened
variant.

The "halflast" surgery: in saturnin_block_encrypt, the last loop iteration
(i == R-1) performs only S_box + MDS + S_box, skipping the SR / second MDS /
SR_inv / round-constant / key XOR. Decrypt mirrors with
S_box_inv + MDS_inv + S_box_inv on its first iteration (which corresponds to
encrypt's last super-round). Recipe:
variant_workfolder/final_fixes_recommendation.md (Saturnin entry).
"""

import os
import re
import sys


def patch_cascade_r(ref_dir, r):
    path = os.path.join(ref_dir, "encrypt.c")
    src = open(path).read()
    new_src, n = re.subn(
        r"^#define SATURNIN_CASCADE_R[ \t]+10$",
        "#define SATURNIN_CASCADE_R        %d" % r,
        src,
        flags=re.MULTILINE,
    )
    assert n == 1, "cascade_r patch did not match (n=%d)" % n
    with open(path, "w") as f:
        f.write(new_src)


def patch_halflast(ref_dir):
    path = os.path.join(ref_dir, "saturnin.c")
    src = open(path).read()

    # --- saturnin_block_encrypt: special-case the LAST iteration of the loop. ---
    enc_pat = re.compile(
        r"(for \(i = 0; i < R; i \+\+\) \{\s*"
        r"/\*\s*\* Even round\.\s*\*/\s*"
        r"S_box\(xb\);\s*"
        r"MDS\(xb\);\s*"
        r"/\*\s*\* Odd round\.\s*\*/\s*"
        r"S_box\(xb\);)\s*"
        r"(if \(\(i & 1\) == 0\))",
        re.MULTILINE,
    )
    src, n = enc_pat.subn(
        r"\1\n\t\tif (i == R - 1) { continue; }\n\t\t\2",
        src,
    )
    assert n == 1, "encrypt patch did not match (n=%d)" % n

    # --- saturnin_block_decrypt: special-case the FIRST iteration (i == R-1). ---
    dec_pat = re.compile(
        r"(for \(i = R - 1; i >= 0; i\s*--\s*\) \{)\s*"
        r"(/\*\s*\* Odd round\.\s*\*/)",
        re.MULTILINE,
    )
    replacement = (
        r"\1\n"
        r"\t\tif (i == R - 1) {\n"
        r"\t\t\tS_box_inv(xb);\n"
        r"\t\t\tMDS_inv(xb);\n"
        r"\t\t\tS_box_inv(xb);\n"
        r"\t\t\tcontinue;\n"
        r"\t\t}\n"
        r"\t\t\2"
    )
    src, n = dec_pat.subn(replacement, src)
    assert n == 1, "decrypt patch did not match (n=%d)" % n

    with open(path, "w") as f:
        f.write(src)


def main():
    ref_dir, cascade_r, halflast = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    patch_cascade_r(ref_dir, cascade_r)
    if halflast == "1":
        patch_halflast(ref_dir)
    print(
        "patch_saturnin: applied (R=%d halflast=%s)" % (cascade_r, halflast),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
