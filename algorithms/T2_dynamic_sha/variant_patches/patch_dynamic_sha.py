#!/usr/bin/env python3
"""Generation-time weakening patcher for Dynamic SHA (NIST SHA-3 Round 1).

Reduces the compression-function round count from the full-strength 48 to a
band-specific value. The reference implementation (dsha_ref.h) contains TWO
round loops -- one in sha32_compile (256-bit digest, the CLI default) and one
in sha64_compile (512-bit digest):

    for ( i=0; i<48; i++ ) {     # sha32_compile  (line ~198)
    for (i=0;i<48;i++)           # sha64_compile  (line ~264)

Both must be patched, kept equal. Reducing rounds is safe: the code indexes
tt[i/16] (i/16 in {0,1,2} for any i<48) and w[i%16], both in-bounds for any
round count 1..48.

Usage:
    patch_dynamic_sha.py <path-to-dsha_ref.h> <rounds>

Asserts that EXACTLY two occurrences were rewritten; fails loudly otherwise so
generation aborts rather than silently shipping an unweakened variant.
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_dynamic_sha.py <dsha_ref.h> <rounds>\n")
        return 2

    path = sys.argv[1]
    rounds = int(sys.argv[2])
    if not (1 <= rounds <= 48):
        sys.stderr.write(
            f"error: rounds must be in 1..48 (full strength is 48), got {rounds}\n"
        )
        return 2

    with open(path, "r", encoding="latin-1") as fh:
        src = fh.read()

    # Match a C for-loop of the form  for ( i = 0 ; i < 48 ; i++ )  with
    # arbitrary whitespace, capturing the prefix up to (and including) the
    # "i<" and the suffix from ";" onward, so only the bound literal changes.
    pattern = re.compile(
        r"(for\s*\(\s*i\s*=\s*0\s*;\s*i\s*<\s*)48(\s*;\s*i\s*\+\+\s*\))"
    )

    new_src, n = pattern.subn(rf"\g<1>{rounds}\g<2>", src)

    if n != 2:
        sys.stderr.write(
            f"error: expected exactly 2 round-loop substitutions, made {n}. "
            "Refusing to repack a mis-patched archive.\n"
        )
        return 1

    with open(path, "w", encoding="latin-1") as fh:
        fh.write(new_src)

    sys.stderr.write(f"patched 2 round loops to {rounds} rounds in {path}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
