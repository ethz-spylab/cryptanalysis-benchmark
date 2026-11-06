#!/usr/bin/env python3
"""Reduce the inner Simon round count R per SimP Feistel step in Oribatida.

Edits the single loop bound in SimP_round() inside SimP_192.h:
    for(i = 0; i < 26; i++)   ->   for(i = 0; i < <R>; i++)

This is the PRIMARY KNOB from algorithm_scaling_down/nist_lwc/oribatida.txt:
the SimP-192 permutation's only nonlinear mixing is the Simon round function,
so total differential resistance scales with steps x R (4R for the dominant
SimP_4). The round-constant stride literal `26` in `z[((26*round)+i)%62]` is
deliberately LEFT UNCHANGED (it still selects distinct constants mod 62).

Usage: patch_oribatida.py <path/to/SimP_192.h> <R>
Fails loudly (non-zero exit) if it does not make exactly one substitution.
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_oribatida.py <SimP_192.h> <R>\n")
        return 2

    path, r = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"\d+", r):
        sys.stderr.write(f"error: R must be a positive integer, got {r!r}\n")
        return 2

    with open(path, "r") as f:
        src = f.read()

    # Match only the SimP_round loop bound, NOT the `26 * round` z-index stride.
    pattern = re.compile(r"for\(i = 0; i < 26; i\+\+\)")
    new_src, n = pattern.subn(f"for(i = 0; i < {r}; i++)", src)
    if n != 1:
        sys.stderr.write(
            f"error: expected exactly 1 substitution in {path}, made {n}\n"
        )
        return 1

    with open(path, "w") as f:
        f.write(new_src)
    sys.stderr.write(f"patched {path}: Simon round count -> {r}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
