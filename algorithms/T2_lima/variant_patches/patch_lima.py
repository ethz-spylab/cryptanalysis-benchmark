#!/usr/bin/env python3
"""Scale-down patcher for LIMA-sp (Ring-LWE KEM, NIST/EncapCCA tree).

LIMA-sp couples the ring dimension N to a matched NTT-friendly prime modulus q
and to four primitive-root "seed" constants (alpha0/alpha1/beta0/beta1).  The
shipped build selects Lima_sp__1018 via `-DLIMASZ=1018`.  This script REPLACES
that parameter set in-place with a weakened (smaller-N) set, keeping every name
the build/dispatch logic relies on (struct `lima_sp_1018`, fft table
`lima_fft_sp_1018`, modulus variable `mod12521473`, tag byte 2, `LIMASZ==1018`
api.h arm) so only numeric constants change.

For each band the constants are pre-computed (see the repo report) such that:
  * p = N+1 is a SAFE prime (p and (p-1)/2 prime)            -> valid LIMA-sp ring
  * q is prime, q == 1 (mod 2p) and q == 1 (mod M=2^e)       -> NTT roots exist
  * e = ceil(log2(2p-1)), M = 2^e                            -> Bluestein length
  * alpha0 = primitive 2p-th root of unity mod q, alpha1 = alpha0^-1
  * beta0  = primitive  M-th  root of unity mod q, beta1  = beta0^-1
  * log256_q (t) stays 3 bytes, so serialization scales cleanly with N.

The CCA encapsulation seed length is reduced 48 -> 32 bytes (kem.c) so the
encrypted message ell = 8*32 = 256 <= N for every band (the upstream 48-byte
seed needs N >= 384, which the easy/medium bands fall below).  The shared
secret CRYPTO_BYTES stays 32.

Usage:  patch_lima.py <ExtractRoot=.../Lima> <band: easy|medium|hard>
Fails loudly (non-zero exit) if any expected substitution count is wrong, so a
broken patch aborts generation instead of silently shipping an unweakened set.
"""

import os
import sys

# band -> parameters (N, e, q, alpha0, alpha1, beta0, beta1, sizes)
# Sizes:  t=3 ; ell=256 (seed_len 32) ;
#   PK = 1 + 2*t*N ; SK = 1 + 3*t*N ; CT = 3 + t*ell + t*N
BANDS = {
    "easy": dict(  # N=262 p=263(safe) q=9695233~2^23.21  -> core-SVP ~2^34
        N=262,
        e=10,
        q=9695233,
        a0=993268,
        a1=2270620,
        b0=7087084,
        b1=9199113,
        sk=2359,
        pk=1573,
        ct=1557,
    ),
    "medium": dict(  # N=382 p=383(safe) q=12942337~2^23.63 -> core-SVP ~2^50
        N=382,
        e=10,
        q=12942337,
        a0=7727168,
        a1=6417516,
        b0=4595133,
        b1=8963099,
        sk=3439,
        pk=2293,
        ct=1917,
    ),
    "hard": dict(  # N=502 p=503(safe) q=10816513~2^23.37 -> core-SVP ~2^66
        N=502,
        e=10,
        q=10816513,
        a0=4695314,
        a1=887989,
        b0=3871837,
        b1=8702360,
        sk=4519,
        pk=3013,
        ct=2277,
    ),
}


def sub(text, old, new, path, expected):
    n = text.count(old)
    if n != expected:
        raise SystemExit(
            f"FATAL [{path}]: expected {expected} occurrence(s) of {old!r}, "
            f"found {n}. Upstream layout changed; refusing to ship."
        )
    return text.replace(old, new)


def patch_file(path, edits):
    with open(path, "r") as f:
        text = f.read()
    for old, new, expected in edits:
        text = sub(text, old, new, path, expected)
    with open(path, "w") as f:
        f.write(text)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: patch_lima.py <ExtractRoot/Lima> <band>")
    root, band = sys.argv[1], sys.argv[2]
    if band not in BANDS:
        raise SystemExit(f"unknown band {band!r}")
    p = BANDS[band]
    ref = os.path.join(root, "Reference_Implementation")
    lib = os.path.join(ref, "Lib")
    kem = os.path.join(ref, "NIST", "EncapCCA")

    # 1) lima.c — replace the lima_sp_1018 struct initializer + the two
    #    EncodePK/EncodeCT `case 1018:` tag arms (keep struct & fft names).
    new_struct = (
        f"lima_params_t lima_sp_1018 = {{ LIMA_SP, &mod12521473, "
        f"{p['N']}, {p['e']}, {p['a0']}, {p['a1']}, {p['b0']}, {p['b1']}, "
        f"&lima_fft_sp_1018 }};"
    )
    patch_file(
        os.path.join(lib, "lima.c"),
        [
            (
                "lima_params_t lima_sp_1018 = { LIMA_SP, &mod12521473, 1018, 11,  "
                "1561269,   8501297, 9597006, 10910567, &lima_fft_sp_1018 };",
                new_struct,
                1,
            ),
            ("case 1018: B[0]=2; break;", f"case {p['N']}: B[0]=2; break;", 2),
        ],
    )

    # 2) modp.c — repoint the modulus value (keep the variable name).
    patch_file(
        os.path.join(lib, "modp.c"),
        [
            ("mod12521473 = { 12521473, 3 }", f"mod12521473 = {{ {p['q']}, 3 }}", 1),
        ],
    )

    # 3) api.h — new serialized sizes for the LIMASZ==1018 arm.
    patch_file(
        os.path.join(kem, "api.h"),
        [
            ("CRYPTO_SECRETKEYBYTES 9163", f"CRYPTO_SECRETKEYBYTES {p['sk']}", 1),
            ("CRYPTO_PUBLICKEYBYTES 6109", f"CRYPTO_PUBLICKEYBYTES {p['pk']}", 1),
            ("CRYPTO_CIPHERTEXTBYTES 4209", f"CRYPTO_CIPHERTEXTBYTES {p['ct']}", 1),
        ],
    )

    # 4) LimaAPI.c — byte-length-based dispatch pair must match new sizes.
    patch_file(
        os.path.join(lib, "LimaAPI.c"),
        [
            ("sklen==9163 && pklen==6109", f"sklen=={p['sk']} && pklen=={p['pk']}", 1),
        ],
    )

    # 5) kem.c — shrink the CCA encap seed (ell) to 256 bits so ell <= N.
    patch_file(
        os.path.join(kem, "kem.c"),
        [
            ("CRYPTO_BYTES,seed,48,pk", "CRYPTO_BYTES,seed,32,pk", 1),
        ],
    )

    print(f"patched LIMA -> band={band} N={p['N']} q={p['q']}")


if __name__ == "__main__":
    main()
