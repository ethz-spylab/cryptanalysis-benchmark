#!/usr/bin/env python3
"""Vortex easy/medium/hard variant patch (Approach A — reduce AES_ROUNDS).

The reference impl exposes the per-block AES round count as a *runtime*
tunable, `number_of_rounds_g`, initialized in `set_default_parameters()`
(vortex_core.c) to the literal `10`. `Hash()` calls `set_default_parameters()`
before each compression, so rewriting that literal is sufficient to weaken the
permutation. Per algorithm_scaling_down/nist_sha3/round_1/Vortex.txt and the
MEDIUM_VARIANTS_ADDENDUM.md (Vortex (R1) row), the spec values are:

    Hard   (2^60-2^80): AES_ROUNDS = 4
    Medium (2^40-2^60): AES_ROUNDS = 3
    Easy   (2^30-2^40): AES_ROUNDS = 2

This reproduces, at generation time, exactly the substitution the previous
build-time injection performed:

    sed -E 's/number_of_rounds_g[[:space:]]*=[[:space:]]*10;/number_of_rounds_g = <R>;/'

Usage: patch_vortex.py <path-to-vortex_core.c> <rounds>
"""

import re
import sys

PATH = sys.argv[1]
ROUNDS = int(sys.argv[2])

src = open(PATH).read()

# Match the upstream default initializer, allowing arbitrary whitespace around
# the `=` (mirrors the [[:space:]]* in the original sed expression). The
# replacement normalizes to single spaces, byte-identical to the old sed.
pattern = re.compile(r"number_of_rounds_g\s*=\s*10;")
new_src, n = pattern.subn(f"number_of_rounds_g = {ROUNDS};", src)
assert n >= 1, f"Expected >=1 occurrence of 'number_of_rounds_g = 10;', found {n}"

open(PATH, "w").write(new_src)
