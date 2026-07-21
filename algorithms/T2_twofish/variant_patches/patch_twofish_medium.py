#!/usr/bin/env python3
"""Twofish medium variant patch (R=3, odd rounds).

The Schneier reference rejects odd round counts via `(rounds & 1)`
guards in `blockEncrypt` / `blockDecrypt` (a designer's safety net for
whitening alignment). The Feistel structure itself is well-defined for
odd R; we just need to compensate for the half-swap that an extra
"unswap" pass would normally perform.

Per `variant_workfolder/final_fixes_recommendation.md` (Twofish recipe):
1. delete the `(rounds & 1)` clause from both blockEncrypt and
   blockDecrypt;
2. when R is odd, swap (x[0],x[1]) <-> (x[2],x[3]) in blockEncrypt
   *after* the round loop but *before* the output-whitening write-out;
3. mirror the same swap in blockDecrypt right after the input read /
   output-whitening XOR but *before* the round loop.

The swap is its own inverse, so encrypt-then-decrypt composes back to
the identity.

Usage: python3 patch_twofish_medium.py twofish.c
"""

import re
import sys

ENC_SWAP = """\
#if FEISTEL
		x[0] = ROR(x[0],8);                     /* "final permutation" */
		x[1] = ROL(x[1],8);
		x[2] = ROR(x[2],8);
		x[3] = ROL(x[3],8);
#endif
		if (rounds & 1)                /* medium-variant odd-R parity fix */
			{
			tmp = x[0]; x[0] = x[2]; x[2] = tmp;
			tmp = x[1]; x[1] = x[3]; x[3] = tmp;
			}
"""

DEC_SWAP_INSERT = """\
		if (rounds & 1)                /* medium-variant odd-R parity fix */
			{
			t0 = x[0]; x[0] = x[2]; x[2] = t0;
			t0 = x[1]; x[1] = x[3]; x[3] = t0;
			}

"""


def main():
    path = sys.argv[1]
    with open(path) as f:
        src = f.read()

    # 1. Drop the `(rounds & 1)` guard in both blockEncrypt and
    #    blockDecrypt. Upstream renders it without a space inside the
    #    parens and with a leading " || " sequence.
    guarded = "(rounds < 2) || (rounds > MAX_ROUNDS) || (rounds&1)"
    relaxed = "(rounds < 2) || (rounds > MAX_ROUNDS)"
    if src.count(guarded) != 2:
        raise SystemExit(
            f"expected exactly 2 occurrences of `(rounds&1)` guard, got {src.count(guarded)}"
        )
    src = src.replace(guarded, relaxed)

    # 2. Replace the encrypt-side `#if FEISTEL ... #endif` final-perm
    #    block with that same block followed by the parity swap. The
    #    block ends with `x[3] = ROL(x[3],8);\n\t#endif\n` and is
    #    immediately followed by the output-whitening for-loop. There is
    #    only one such #if FEISTEL block in the file (the
    #    decrypt-side does its rotations inside the round loop).
    enc_pattern = re.compile(
        r"#if FEISTEL\n"
        r"\t\tx\[0\] = ROR\(x\[0\],8\);[^\n]*\n"
        r"\t\tx\[1\] = ROL\(x\[1\],8\);\n"
        r"\t\tx\[2\] = ROR\(x\[2\],8\);\n"
        r"\t\tx\[3\] = ROL\(x\[3\],8\);\n"
        r"#endif\n"
    )
    matches = enc_pattern.findall(src)
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly 1 encrypt-side final-permutation block, got {len(matches)}"
        )
    src = enc_pattern.sub(ENC_SWAP, src, count=1)

    # 3. Insert the decrypt-side parity swap right after the input
    #    read/whitening loop and before the round loop.
    dec_anchor = (
        "\t\tfor (i=0;i<BLOCK_SIZE/32;i++)\t/* copy in the block, add whitening */\n"
        "\t\t\tx[i]=Bswap(((DWORD *)input)[i]) ^ key->subKeys[OUTPUT_WHITEN+i];\n\n"
    )
    if src.count(dec_anchor) != 1:
        raise SystemExit(
            f"expected exactly 1 decrypt-side input-whitening block, got {src.count(dec_anchor)}"
        )
    src = src.replace(dec_anchor, dec_anchor + DEC_SWAP_INSERT, 1)

    with open(path, "w") as f:
        f.write(src)


if __name__ == "__main__":
    main()
