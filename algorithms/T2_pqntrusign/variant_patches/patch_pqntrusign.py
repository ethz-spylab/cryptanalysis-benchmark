#!/usr/bin/env python3
"""
Scale-down patcher for pqNTRUsign (Gaussian-1024).

Reduces the NTRU ring degree N (the primary security parameter). Because the
reference NTT is a naive O(N^2) evaluation at the N roots of x^N+1 mod q
(q = 65537), the precomputed roots/invntt tables and inv_N must be regenerated
for the new degree. This script regenerates them, updates the parameter struct
(N, N_bits, padded_N, inv_N, and optionally the product-form weight d), and
fixes the hardcoded key/signature byte sizes in api.h.

Constraints:
  * q = 65537 = 2^16 + 1, so a negacyclic NTT exists only when 2N | 2^16,
    i.e. N must be a power of two. (Non-power-of-two N has no NTT here.)
  * pol_gen_flat needs 2*d+1 nonzero coefficients to fit in N, i.e. 2*d+1 < N.

Usage:
  patch_pqntrusign.py <ReferenceImplementationRoot> <N> [<d>]
"""
import re
import sys

Q = 65537


def egcd(a, b):
    if b == 0:
        return (a, 1, 0)
    g, x, y = egcd(b, a % b)
    return (g, y, x - (a // b) * y)


def inv_mod(a):
    g, x, _ = egcd(a % Q, Q)
    if g not in (1, -1):
        raise ValueError(f"{a} not invertible mod {Q}")
    return x % Q


def gen_tables(N):
    if N <= 0 or (N & (N - 1)) != 0:
        raise ValueError(
            f"N={N} is not a power of two; q={Q} supports the negacyclic "
            f"NTT only for power-of-two N (need 2N | 2^16)."
        )
    order = 2 * N
    if (Q - 1) % order != 0:
        raise ValueError(f"2N={order} does not divide q-1={Q-1}")
    # 3 is a primitive root mod 65537; w is a primitive 2N-th root of unity.
    w = pow(3, (Q - 1) // order, Q)
    assert pow(w, order, Q) == 1 and pow(w, order // 2, Q) != 1
    roots = [0] * N
    for i in range(N // 2):
        r = pow(w, 2 * i + 1, Q)        # an odd power of w -> a root of x^N+1
        roots[i] = r
        roots[N - 1 - i] = (Q - r) % Q  # the C NTT requires roots[N-1-i] = -roots[i]
    assert len(set(roots)) == N, "roots not distinct"
    for r in roots:
        assert pow(r, N, Q) == Q - 1, "not a root of x^N+1"
    inv_roots = [inv_mod(r) for r in roots]
    inv_N = inv_mod(N)
    return roots, inv_roots, inv_N


def fmt_array(name, N, values):
    body = ", ".join(str(v) for v in values)
    return f"static int64_t {name}[{N}] = \n{{{body}}};"


def patch_param_c(path, N, d):
    src = open(path).read()
    roots, inv_roots, inv_N = gen_tables(N)

    # 1) Replace the two precomputed tables (keep the original variable names).
    src, n = re.subn(
        r"static int64_t roots1024\[\d+\]\s*=\s*\n\{[^}]*\};",
        fmt_array("roots1024", N, roots),
        src,
    )
    assert n == 1, f"roots1024 array replaced {n} times (expected 1)"
    src, n = re.subn(
        r"static int64_t invntt1024\[\d+\]\s*=\s*\n\{[^}]*\};",
        fmt_array("invntt1024", N, inv_roots),
        src,
    )
    assert n == 1, f"invntt1024 array replaced {n} times (expected 1)"

    # 2) Struct fields (both Gaussian_ and Uniform_ entries get patched).
    nbits = N.bit_length() - 1
    src, n = re.subn(
        r"\b10,(\s*/\* bitlength of N \*/)",
        f"{nbits},\\1",
        src,
    )
    assert n >= 1, "N_bits field not found"
    src, n = re.subn(
        r"\b1024,(\s*/\* ring degree \*/)",
        f"{N},\\1",
        src,
    )
    assert n >= 1, "ring degree field not found"
    src, n = re.subn(
        r"\b1024,(\s*/\* # Polynomial coefficients for Karatsuba \*/)",
        f"{N},\\1",
        src,
    )
    assert n >= 1, "padded_N field not found"
    if d is not None:
        src, n = re.subn(
            r"\b205,(\s*/\* Product form \+1/-1 counts \*/)",
            f"{d},\\1",
            src,
        )
        assert n >= 1, "product-form d field not found"
    # inv_N is the unlabeled value right after the invntt1024 pointer field.
    src, n = re.subn(
        r"(invntt1024,\s*\n\s*)65473,",
        f"\\g<1>{inv_N},",
        src,
    )
    assert n >= 1, "inv_N field not found"

    open(path, "w").write(src)
    print(f"[param.c] N={N} N_bits={nbits} padded_N={N} inv_N={inv_N}"
          + (f" d={d}" if d is not None else ""))


def patch_api_h(path, N):
    pk = 2 * N + 17                                  # 1 + (N+8)*2
    sk = (N // 5) * 2 + 4 + N // 8 + (N + 8) * 2
    src = open(path).read()
    for macro, val in (
        ("CRYPTO_SECRETKEYBYTES", sk),
        ("CRYPTO_PUBLICKEYBYTES", pk),
        ("CRYPTO_BYTES", pk),
    ):
        src, n = re.subn(
            rf"(#define {macro}\s+)\d+",
            rf"\g<1>{val}",
            src,
        )
        assert n == 1, f"{macro} replaced {n} times (expected 1)"
    open(path, "w").write(src)
    print(f"[api.h] CRYPTO_PUBLICKEYBYTES=CRYPTO_BYTES={pk} "
          f"CRYPTO_SECRETKEYBYTES={sk}")


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: patch_pqntrusign.py <RefImplRoot> <N> [<d>]")
    ref = sys.argv[1].rstrip("/")
    N = int(sys.argv[2])
    d = int(sys.argv[3]) if len(sys.argv) > 3 else None
    patch_param_c(f"{ref}/common/param.c", N, d)
    patch_api_h(f"{ref}/Gaussian-1024/api.h", N)


if __name__ == "__main__":
    main()
