#!/usr/bin/env python3
"""Scale-down patcher for Post-quantum RSA (pqrsa15 KEM).

Collapses the many-prime modulus N = p_0 * ... * p_{K-1} to ordinary balanced
two-prime RSA (K = 2) and shrinks the per-prime byte width PBYTES so the modulus
bit-length N = K*PBYTES*8 = 16*PBYTES drops to a GNFS-factorable size.

Edits three shipped headers inside the pqrsa15 source dir and keeps the dependent
size macros consistent (otherwise the `#if` static asserts in dec.c fail the build):
    internal.h            : K, PBYTES
    crypto_kem_pqrsa15.h  : *_SECRETKEYBYTES = 3*K*PBYTES, *_PUBLICKEYBYTES =
                            *_CIPHERTEXTBYTES = K*PBYTES
    api.h                 : CRYPTO_SECRETKEYBYTES / PUBLICKEYBYTES / CIPHERTEXTBYTES
    dec.c                 : guard for the K/8 batch loop in remainders() (upstream
                            assumes K>=8; with K=2 it computes tree=K/8=0 and spins
                            forever in keygen). Guard is a no-op for K>=8.

Usage:
    patch_pqrsa.py <pqrsa15_src_dir> <PBYTES>   (K is forced to 2)

Fails loudly (non-zero substitution assert) if any expected edit did not apply.
"""
import re
import sys


def sub_assert(pattern, repl, text, label):
    new, n = re.subn(pattern, repl, text)
    if n == 0:
        sys.exit(f"FATAL: pattern for '{label}' matched 0 times")
    return new


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: patch_pqrsa.py <pqrsa15_src_dir> <PBYTES>")
    src = sys.argv[1].rstrip("/")
    pbytes = int(sys.argv[2])
    K = 2
    pub = ct = K * pbytes          # PUBLICKEYBYTES == CIPHERTEXTBYTES == K*PBYTES
    sk = 3 * K * pbytes            # SECRETKEYBYTES == 3*K*PBYTES

    # internal.h
    p = f"{src}/internal.h"
    with open(p) as f:
        t = f.read()
    t = sub_assert(r"#define\s+K\s+\d+", f"#define K {K}", t, "internal.h K")
    t = sub_assert(r"#define\s+PBYTES\s+\d+", f"#define PBYTES {pbytes}", t,
                   "internal.h PBYTES")
    with open(p, "w") as f:
        f.write(t)

    # crypto_kem_pqrsa15.h
    p = f"{src}/crypto_kem_pqrsa15.h"
    with open(p) as f:
        t = f.read()
    t = sub_assert(r"(#define\s+crypto_kem_pqrsa15_ref_SECRETKEYBYTES\s+)\d+",
                   rf"\g<1>{sk}", t, "kem.h SECRETKEYBYTES")
    t = sub_assert(r"(#define\s+crypto_kem_pqrsa15_ref_PUBLICKEYBYTES\s+)\d+",
                   rf"\g<1>{pub}", t, "kem.h PUBLICKEYBYTES")
    t = sub_assert(r"(#define\s+crypto_kem_pqrsa15_ref_CIPHERTEXTBYTES\s+)\d+",
                   rf"\g<1>{ct}", t, "kem.h CIPHERTEXTBYTES")
    with open(p, "w") as f:
        f.write(t)

    # dec.c -- fix the K<8 infinite loop in remainders().
    # Upstream: `long long tree = K / 8;` then chunks the K primes in batches of
    # that size. For K<8 (our K=2) the batch size rounds to 0 and the while loop
    # never makes progress -> keygen hangs. Insert a guard that falls back to the
    # whole batch when tree==0. No-op for K>=8 (tree>=1 already).
    p = f"{src}/dec.c"
    with open(p) as f:
        t = f.read()
    t = sub_assert(
        r"long long tree = K / 8;",
        "long long tree = K / 8;\n    if (tree < 1) tree = K; "
        "/* K<8: K/8 rounds to 0; process whole batch at once */",
        t, "dec.c remainders K/8 guard")
    with open(p, "w") as f:
        f.write(t)

    # api.h
    p = f"{src}/api.h"
    with open(p) as f:
        t = f.read()
    t = sub_assert(r"(#define\s+CRYPTO_SECRETKEYBYTES\s+)\d+", rf"\g<1>{sk}", t,
                   "api.h SECRETKEYBYTES")
    t = sub_assert(r"(#define\s+CRYPTO_PUBLICKEYBYTES\s+)\d+", rf"\g<1>{pub}", t,
                   "api.h PUBLICKEYBYTES")
    t = sub_assert(r"(#define\s+CRYPTO_CIPHERTEXTBYTES\s+)\d+", rf"\g<1>{ct}", t,
                   "api.h CIPHERTEXTBYTES")
    with open(p, "w") as f:
        f.write(t)

    print(f"patched: K={K} PBYTES={pbytes} -> N={16*pbytes}-bit "
          f"(PUB=CT={pub}, SK={sk})")


if __name__ == "__main__":
    main()
