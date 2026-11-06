#!/usr/bin/env python3
"""Rewrite DAGS's param.h for a scaled-down error weight n0_w.

DAGS (the DAG 96 / dags3 parameter set shipped here) is a code-based KEM built on
a dyadic Generalised-Srivastava code. Its public generator G is an [n=1216,
k=512] code over GF(2^6); encapsulation forms the ciphertext c = u*G + e where e
is a fixed-weight error vector of Hamming weight n0_w (=176 at full strength), and
recovering the shared secret from a ciphertext is exactly the fixed-weight
syndrome-decoding / information-set-decoding (ISD) problem on that code. The ISD
work factor for a [1216,512] code drops monotonically as the error weight n0_w
shrinks well below its design value, so lowering n0_w is a clean, monotone
weakening knob for the FOSS-reachable (message / shared-secret recovery) attack
surface. (The purely structural key-recovery attacks on DAGS — Bardet et al.,
Barelli-Couvreur — are Magma-bound and n0_w-independent, so they are unaffected;
they sit outside the in-budget attack surface these bands are meant to scale.)

Crucially, n0_w appears ONLY in encapsulation.c (how many errors are injected) and
decapsulation.c (the weight check + the re-derivation of the error from sigma);
it is never read by key_gen.c. Reducing it therefore leaves the delicate dyadic
key generation, the field-arithmetic tables and every derived buffer size
completely untouched, and it only makes decoding *easier* (fewer errors than the
GS decoder's capacity), so the KEM round-trip stays valid. Nothing else in the
source depends on n0_w, so this patcher rewrites exactly one line.

param.h holds two `#define n0_w` lines: the active DAG 96 value (176) and a
commented-out DAG 128 value (352, inside a /* ... */ block). We target the active
`#define n0_w 176` by exact substring match and assert it occurs exactly once, so
a stale or already-patched header can never silently produce an unweakened (or
mis-patched) variant. The edit is a plain substring replacement, which is
agnostic to the source's CRLF line endings (DAGS ships DOS/CRLF and build_cli.sh
normalises to LF only after extraction).

Usage:
    patch_dags.py <path/to/param.h> <n0_w>
"""

import sys

BASE_N0_W = 176  # shipped DAG 96 full-strength error weight


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: patch_dags.py <param.h> <n0_w>")
    path = sys.argv[1]
    try:
        w = int(sys.argv[2])
    except ValueError:
        sys.exit(f"ERROR: n0_w={sys.argv[2]!r} is not an integer")

    # Validity: strictly weaker than the shipped base, and a meaningful positive
    # weight. (random_e places up to n0_w nonzero positions; the decoder corrects
    # any weight <= its capacity, so any 0 < w < 176 round-trips.)
    if w <= 0:
        sys.exit(f"ERROR: n0_w={w} must be positive")
    if w >= BASE_N0_W:
        sys.exit(
            f"ERROR: n0_w={w} must be < {BASE_N0_W} (the shipped "
            "full-strength base); refusing to emit an unweakened variant"
        )

    with open(path, "r", newline="") as f:
        text = f.read()

    old = f"#define n0_w {BASE_N0_W}"
    new = f"#define n0_w {w}"
    count = text.count(old)
    if count != 1:
        sys.exit(
            f"ERROR: expected exactly 1 occurrence of {old!r}, found "
            f"{count} in {path}; param.h layout changed -- refusing to "
            "continue"
        )

    text = text.replace(old, new)
    with open(path, "w", newline="") as f:
        f.write(text)

    print(
        f"patched {path}: n0_w {BASE_N0_W} -> {w} "
        f"([1216,512] GF(2^6) GS code; ISD error weight lowered)"
    )


if __name__ == "__main__":
    main()
