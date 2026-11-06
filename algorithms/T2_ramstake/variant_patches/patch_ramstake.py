#!/usr/bin/env python3
"""Scaling-down patcher for Ramstake RS 216091.

Sets both secret Hamming-weight masses to the band value w:
    #define RAMSTAKE_MULTIPLICATIVE_MASS <w>
    #define RAMSTAKE_ADDITIVE_MASS       <w>

Per algorithm_scaling_down/nist_pqc/ramstake.txt, the secret weight w is the
binding security knob (MITM cost C(n, w/2); Beunardeau lattice). The Mersenne
prime exponent RAMSTAKE_MODULUS_BITSIZE = 216091 is deliberately left untouched.
The derived macro RAMSTAKE_KEYGEN_RANDOM_BYTES updates automatically.

Usage: patch_ramstake.py <path/to/ramstake.h> <w>
Fails loudly (nonzero exit) if it does not change exactly the two expected
defines.
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_ramstake.py <ramstake.h> <w>\n")
        return 2

    path = sys.argv[1]
    w = int(sys.argv[2])
    if w < 2 or w % 2 != 0:
        sys.stderr.write(f"refusing w={w}: must be even and >= 2\n")
        return 2

    with open(path, "r") as f:
        text = f.read()

    total = 0
    for macro in ("RAMSTAKE_MULTIPLICATIVE_MASS", "RAMSTAKE_ADDITIVE_MASS"):
        pat = re.compile(
            r"^(#define\s+" + re.escape(macro) + r"\s+)\d+\s*$",
            re.MULTILINE,
        )
        text, n = pat.subn(r"\g<1>" + str(w), text)
        if n != 1:
            sys.stderr.write(f"FATAL: expected exactly 1 match for {macro}, got {n}\n")
            return 1
        total += n

    if total != 2:
        sys.stderr.write(f"FATAL: expected 2 substitutions, made {total}\n")
        return 1

    with open(path, "w") as f:
        f.write(text)

    sys.stderr.write(f"patched {path}: both masses -> {w}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
