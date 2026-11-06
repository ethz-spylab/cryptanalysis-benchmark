#!/usr/bin/env python3
"""Generation-time weakening patcher for FROG (AES candidate, FROGC-2).

FROG is an 8-iteration substitution/permutation block cipher (FROG-128, 16-byte
block, 16-byte key). Its round/iteration count is a single macro in the upstream
header AES.H:

    #define numIter 8

`numIter` is the sole knob that governs the whole cipher: the internal key type
is declared `typedef tIterKey tInternalKey[numIter];`, the key schedule
(makeInternalKey / hashKey via `internalKeyLen = sizeof(tInternalKey)`) sizes and
fills exactly numIter iteration keys, and encryptFrog / decryptFrog both loop
`for (iteration = 0; iteration < numIter; ...)`. Reducing numIter therefore keeps
encrypt/decrypt fully self-consistent (the internal structure is regenerated per
numIter) while weakening the cipher: round-reduced FROG becomes differentially
and linearly weak for most keys, and the weakness broadens as iterations drop.

Usage:
    patch_frog.py <path-to-AES.H> <numIter>

Asserts that EXACTLY one occurrence was rewritten; fails loudly otherwise so
generation aborts rather than silently shipping an unweakened variant.
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_frog.py <AES.H> <numIter>\n")
        return 2

    path = sys.argv[1]
    num_iter = int(sys.argv[2])
    if not (1 <= num_iter < 8):
        sys.stderr.write(
            f"error: numIter must be in 1..7 (full strength is 8), got {num_iter}\n"
        )
        return 2

    with open(path, "r", encoding="latin-1") as fh:
        src = fh.read()

    # Match  #define numIter 8  with arbitrary intra-line whitespace, replacing
    # only the value literal so nothing else in the header is disturbed.
    pattern = re.compile(r"(#define\s+numIter\s+)8\b")
    new_src, n = pattern.subn(rf"\g<1>{num_iter}", src)

    if n != 1:
        sys.stderr.write(
            f"error: expected exactly 1 numIter substitution, made {n}. "
            "Refusing to repack a mis-patched archive.\n"
        )
        return 1

    with open(path, "w", encoding="latin-1") as fh:
        fh.write(new_src)

    sys.stderr.write(f"patched numIter to {num_iter} in {path}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
