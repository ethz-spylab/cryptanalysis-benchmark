#!/usr/bin/env python3
"""Rewrite Rainbow's rainbow_config.h for a scaled-down (v1, o1, o2) layer set.

Rainbow's rainbow_config.h defines the three primary layer sizes (_V1, _O1, _O2)
plus the field/hash length; EVERY other size constant the scheme uses is derived
from those three by C-preprocessor formulas already present in the header, e.g.

    _V2        = _V1 + _O1
    _V1_BYTE   = _V1 / 2          (GF(16): 2 nibbles per byte)
    _O1_BYTE   = _O1 / 2
    _O2_BYTE   = _O2 / 2
    _PUB_N     = _V1 + _O1 + _O2      _PUB_N_BYTE = _PUB_N / 2
    _PUB_M     = _O1 + _O2            _PUB_M_BYTE = _PUB_M / 2
    _SIGNATURE_BYTE = _PUB_N_BYTE + _SALT_BYTE
    _PUB_KEY_LEN    = TERMS_QUAD_POLY(_PUB_N) * _PUB_M_BYTE + 1
    _SEC_KEY_LEN    = sizeof(rainbow_key) + 1     (rainbow_16.h, from the above)

So the ONLY thing this patcher must change is the active _RAINBOW16_32_32_32
block's _V1 / _O1 / _O2; the compiler recomputes every dependent constant, key
buffer size, and serialized length automatically. _HASH_LEN is left at 32
(SHA-256): the signer expands/truncates the 32-byte digest down to _PUB_M_BYTE
bytes via expand_sha2(), which is valid for any _PUB_M_BYTE <= 32, and every
scaled band has _PUB_M_BYTE = (o1+o2)/2 < 32. The field _GFSIZE=16 is fixed so
the GF(16) arithmetic tables in gf16.h stay valid.

Hard constraint: GF(16) packs two field elements per byte, so v1, o1, o2 must
each be EVEN (the _*_BYTE = _*/2 integer divisions must be exact). The two-layer
Oil-and-Vinegar structure additionally needs o1,o2 >= 1 and v1 >= o1 so each
layer's linear back-substitution is solvable. The patcher enforces all of these.

Usage:
    patch_rainbow.py <path/to/rainbow_config.h> <v1> <o1> <o2>

It rewrites the three #define lines under the _RAINBOW16_32_32_32 block and
asserts it changed exactly three lines (fails loudly otherwise), so a stale or
already-patched header can never silently produce an unweakened variant.
"""

import re
import sys


def main():
    if len(sys.argv) != 5:
        sys.exit("usage: patch_rainbow.py <rainbow_config.h> <v1> <o1> <o2>")
    path = sys.argv[1]
    v1, o1, o2 = (int(x) for x in sys.argv[2:5])

    # Validity checks (fail loudly rather than emit a broken/unweakened build).
    for name, val in (("v1", v1), ("o1", o1), ("o2", o2)):
        if val <= 0:
            sys.exit(f"ERROR: {name}={val} must be positive")
        if val % 2 != 0:
            sys.exit(
                f"ERROR: {name}={val} must be EVEN (GF(16) packs 2 "
                "nibbles/byte; _*_BYTE = _*/2 must be exact)"
            )
    if v1 < o1:
        sys.exit(
            f"ERROR: v1={v1} must be >= o1={o1} (layer-1 vinegar count "
            "must cover the oil layer for the OV back-substitution)"
        )
    if (v1, o1, o2) == (32, 32, 32):
        sys.exit(
            "ERROR: (32,32,32) is the shipped full-strength base; refusing "
            "to emit an unweakened variant"
        )

    with open(path, "r") as f:
        text = f.read()

    subs = 0

    def repl_v1(m):
        nonlocal subs
        subs += 1
        return f"#define _V1 {v1}"

    def repl_o1(m):
        nonlocal subs
        subs += 1
        return f"#define _O1 {o1}"

    def repl_o2(m):
        nonlocal subs
        subs += 1
        return f"#define _O2 {o2}"

    # Only the _RAINBOW16_32_32_32 block carries the literal "32" for all three,
    # so these anchored patterns are unique (the 56/48/48 and 76/64/64 blocks
    # use different literals and are inactive #if branches anyway).
    text = re.sub(r"^#define _V1 32$", repl_v1, text, flags=re.M)
    text = re.sub(r"^#define _O1 32$", repl_o1, text, flags=re.M)
    text = re.sub(r"^#define _O2 32$", repl_o2, text, flags=re.M)

    if subs != 3:
        sys.exit(
            f"ERROR: expected 3 substitutions (_V1/_O1/_O2), made {subs} "
            f"in {path}; header layout changed -- refusing to continue"
        )

    with open(path, "w") as f:
        f.write(text)

    n = v1 + o1 + o2
    m = o1 + o2
    print(
        f"patched {path}: v1={v1} o1={o1} o2={o2} "
        f"(n={n} variables, m={m} equations, GF(16))"
    )


if __name__ == "__main__":
    main()
