#!/usr/bin/env python3
"""Patch NTRU-HRSS-KEM's primary lattice parameter `NTRU_N` (the ring degree).

Per algorithm_scaling_down/nist_pqc/ntru_hrss_kem.txt, the only structural knob
is the ring degree N (`#define NTRU_N` in params.h). The modulus stays fixed at
q = 2^13 = 8192 (NTRU_LOGQ = 13): reducing N only widens the
decryption-correctness margin, so q need not change. All key/ciphertext/packing
byte sizes are derived symbolically from NTRU_N in params.h, and every loop in
poly.c / owcpa.c / ntrukem.c iterates over NTRU_N (verified by grep: there is no
hardcoded 701 anywhere in the compiled Reference_Implementation sources — the
only literal `13*i` indexing in poly.c is the q = 2^13 packing, which is kept).

N MUST remain prime: HRSS relies on the factorization x^N - 1 = (x - 1)*Phi_N
and on Phi_N being irreducible mod 2/3 (used in the almost-inverse R2/S3
inversions and the `g = 1 + x + ... + x^{N-1}` = Phi_N generator). The bands use
389 / 269 / 197, all prime.

Usage: patch_ntru_hrss_kem.py <path/to/Reference_Implementation/.../ntruhrss701> <N>

Fails loudly (non-zero exit) if the expected substitution makes zero changes, so
a botched patch can never silently yield an unweakened variant.
"""

import os
import re
import sys


def is_prime(n: int) -> bool:
    if n < 2:
        return False
    i = 2
    while i * i <= n:
        if n % i == 0:
            return False
        i += 1
    return True


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_ntru_hrss_kem.py <ntruhrss701 source dir> <N>\n")
        return 2

    src_dir = sys.argv[1]
    n_val = int(sys.argv[2])

    if not is_prime(n_val):
        sys.stderr.write(
            f"FATAL: NTRU_N={n_val} is not prime (HRSS requires N prime)\n"
        )
        return 2
    # poly arrays are stack-allocated as coeffs[NTRU_N]; keep within sane bounds.
    if not (101 <= n_val <= 701):
        sys.stderr.write(f"FATAL: NTRU_N={n_val} outside expected range [101, 701]\n")
        return 2

    params_h = os.path.join(src_dir, "params.h")
    if not os.path.isfile(params_h):
        sys.stderr.write(f"FATAL: expected source file missing: {params_h}\n")
        return 1

    with open(params_h, "rb") as f:
        data = f.read()

    new_data, n = re.subn(
        rb"#define\s+NTRU_N\s+\d+",
        b"#define NTRU_N %d" % n_val,
        data,
    )
    if n == 0:
        sys.stderr.write(
            f"FATAL: '#define NTRU_N' not found in {params_h}; nothing patched\n"
        )
        return 1

    with open(params_h, "wb") as f:
        f.write(new_data)

    sys.stderr.write(f"patched NTRU_N -> {n_val} ({n} substitution(s)) in {params_h}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
