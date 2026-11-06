#!/usr/bin/env python3
"""Parameterized KCL (OKCN-MLWE) scaling-down patcher.

Reduces the effective Module-LWE dimension n_eff = MLWE_N * MLWE_ELL by editing
parameter.h and (when the ring degree MLWE_N changes) regenerating the four
hard-wired NTT constant tables in polynomial.c for the new degree.

Usage:
    patch_kcl.py <ref_dir> <MLWE_N> <LOG2N> <MLWE_ELL>

<ref_dir> is the extracted .../kem/OKCN-MLWE/ref directory containing
parameter.h and polynomial.c.  The script fails loudly (non-zero exit) if any
expected substitution does not take effect, so generation aborts under `set -e`
rather than silently producing an unweakened variant.

The NTT-table generation reproduces the shipped n=256 tables byte-for-byte when
called with n=256 (validated against the upstream source), so the same formulas
yield correct, self-consistent negacyclic-NTT tables for any admissible degree
(q=7681 admits a negacyclic NTT for every power-of-two n with 2n | q-1).
"""

import re
import sys

Q = 7681
R = 1 << 18  # 2^18 used in the REDC (Montgomery) reduction; q-dependent, n-independent


def egcd(a, b):
    if b == 0:
        return (a, 1, 0)
    g, x, y = egcd(b, a % b)
    return (g, y, x - (a // b) * y)


def inv(a, m):
    g, x, _ = egcd(a % m, m)
    assert g == 1, "no inverse"
    return x % m


def factorize(n):
    facs = set()
    f = 2
    while f * f <= n:
        while n % f == 0:
            facs.add(f)
            n //= f
        f += 1
    if n > 1:
        facs.add(n)
    return facs


def is_primitive(g, order, q):
    if pow(g, order, q) != 1:
        return False
    for p in factorize(order):
        if pow(g, order // p, q) == 1:
            return False
    return True


def find_root(order, q):
    for g in range(2, q):
        if is_primitive(g, order, q):
            return g
    raise RuntimeError("no primitive %d-th root mod %d" % (order, q))


def bitrev(i, bits):
    r = 0
    for _ in range(bits):
        r = (r << 1) | (i & 1)
        i >>= 1
    return r


def gen_tables(n, log2n, phi=None):
    if (Q - 1) % (2 * n) != 0:
        raise RuntimeError("q=%d does not admit a negacyclic NTT for n=%d" % (Q, n))
    if phi is None:
        phi = find_root(2 * n, Q)
    if not is_primitive(phi, 2 * n, Q):
        raise RuntimeError(
            "phi=%d is not a primitive %d-th root mod %d" % (phi, 2 * n, Q)
        )
    omega = (phi * phi) % Q
    phiinv = inv(phi, Q)
    ninv = inv(n, Q)
    R2 = (R * R) % Q

    rot = [bitrev(i, log2n) for i in range(n)]

    phit = [0] * (2 * n)
    for j in range(n):
        phit[j] = (pow(phi, j, Q) * R2) % Q
    for j in range(n, 2 * n):
        phit[j] = (pow(phiinv, 2 * n - 1 - j, Q) * ninv) % Q

    omt = [0] * n
    for j in range(n // 2):
        omt[j] = pow(omega, j, Q)
    for j in range(n // 2, n):
        omt[j] = pow(omega, j + 1, Q)

    tot = [(omt[j] * (1 << 16)) // Q for j in range(n)]
    return rot, phit, omt, tot


def replace_define(text, name, value):
    pat = re.compile(r"(#define\s+" + re.escape(name) + r"\s+)\S+")
    new, count = pat.subn(lambda m: m.group(1) + str(value), text, count=1)
    if count != 1:
        raise RuntimeError("failed to replace #define %s (matched %d)" % (name, count))
    return new


def replace_table(text, name, values):
    # Replace only the brace-enclosed initializer of `const uint16_t NAME[...] = { ... };`
    pat = re.compile(
        r"(const\s+uint16_t\s+" + re.escape(name) + r"\s*\[[^\]]*\]\s*=\s*)\{[^}]*\}"
    )
    body = "{" + ", ".join(str(v) for v in values) + "}"
    new, count = pat.subn(lambda m: m.group(1) + body, text, count=1)
    if count != 1:
        raise RuntimeError("failed to replace table %s (matched %d)" % (name, count))
    return new


def main():
    if len(sys.argv) != 5:
        sys.stderr.write(__doc__)
        return 2
    ref_dir = sys.argv[1]
    n = int(sys.argv[2])
    log2n = int(sys.argv[3])
    ell = int(sys.argv[4])
    if (1 << log2n) != n:
        raise RuntimeError("LOG2N=%d does not match MLWE_N=%d" % (log2n, n))

    param_path = ref_dir + "/parameter.h"
    poly_path = ref_dir + "/polynomial.c"

    with open(param_path) as f:
        param = f.read()
    param = replace_define(param, "LOG2N", log2n)
    param = replace_define(param, "MLWE_N", n)
    param = replace_define(param, "MLWE_ELL", ell)
    with open(param_path, "w") as f:
        f.write(param)

    rot, phit, omt, tot = gen_tables(n, log2n)
    with open(poly_path) as f:
        poly = f.read()
    poly = replace_table(poly, "reverse_order_table", rot)
    poly = replace_table(poly, "phi_table", phit)
    poly = replace_table(poly, "omega_table", omt)
    poly = replace_table(poly, "translated_omega_table", tot)
    with open(poly_path, "w") as f:
        f.write(poly)

    sys.stderr.write(
        "patch_kcl: MLWE_N=%d LOG2N=%d MLWE_ELL=%d  n_eff=%d  (NTT tables regenerated)\n"
        % (n, log2n, ell, n * ell)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
