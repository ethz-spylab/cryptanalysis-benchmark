#!/usr/bin/env python3
"""Weaken a freshly-extracted Classic McEliece mceliece348864 Reference tree to a
reduced Goppa-code parameter set by editing SYS_N / SYS_T (GFBITS stays 12).

Usage:
    patch_mceliece_variant.py <ref_dir> <SYS_N> <SYS_T>

  <ref_dir> is the directory holding params.h / api.h /
  crypto_kem_mceliece348864.h, i.e.
  .../mceliece-20221023/Reference_Implementation/kem/mceliece348864

GFBITS is held at 12, so the GF(2^12) arithmetic in gf.c (its hard-wired
degree-12 modulus x^12 + x^3 + 1) and the Benes support network stay valid and
gf.c is left byte-identical to upstream. Only the two Goppa parameters move; the
KEM byte sizes are macro-derived inside every compiled .c file, but api.h and the
namespaced header hard-code them, so we recompute and substitute those here so
that cli.c's buffers and length checks match the reduced keypair/ciphertext.

Each substitution must hit exactly once or we abort loudly (no silent
unweakened build).
"""

import pathlib
import re
import sys

GFBITS = 12


def kem_byte_sizes(gfbits, sys_n, sys_t):
    irr_bytes = sys_t * 2
    cond_bytes = (1 << (gfbits - 4)) * (2 * gfbits - 1)
    pk_nrows = sys_t * gfbits
    pk_ncols = sys_n - pk_nrows
    pk_row_bytes = (pk_ncols + 7) // 8
    public_key_bytes = pk_nrows * pk_row_bytes
    secret_key_bytes = 40 + irr_bytes + cond_bytes + sys_n // 8
    ciphertext_bytes = (pk_nrows + 7) // 8
    return public_key_bytes, secret_key_bytes, ciphertext_bytes


def subst_once(text, key, val):
    text, n = re.subn(
        rf"#define\s+{re.escape(key)}\s+\d+", f"#define {key} {val}", text
    )
    if n != 1:
        raise SystemExit(
            f"patch_mceliece_variant.py: expected exactly 1 substitution for "
            f"{key}, made {n}"
        )
    return text


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: patch_mceliece_variant.py <ref_dir> <SYS_N> <SYS_T>")

    ref_dir = pathlib.Path(sys.argv[1])
    sys_n = int(sys.argv[2])
    sys_t = int(sys.argv[3])

    if sys_n % 8 != 0:
        raise SystemExit(
            f"patch_mceliece_variant.py: SYS_N={sys_n} must be a multiple of 8"
        )
    if sys_n > (1 << GFBITS):
        raise SystemExit(
            f"patch_mceliece_variant.py: SYS_N={sys_n} cannot exceed 2^GFBITS={1 << GFBITS}"
        )
    k = sys_n - GFBITS * sys_t
    if k <= 0:
        raise SystemExit(
            f"patch_mceliece_variant.py: derived dimension k={k} must be positive"
        )

    pk_b, sk_b, ct_b = kem_byte_sizes(GFBITS, sys_n, sys_t)

    # params.h — the two Goppa-code parameters (GFBITS left untouched at 12).
    params_h = ref_dir / "params.h"
    text = params_h.read_text()
    text = subst_once(text, "SYS_N", sys_n)
    text = subst_once(text, "SYS_T", sys_t)
    params_h.write_text(text)

    # api.h — CRYPTO_* sizes consumed by cli.c's buffers / length checks.
    api_h = ref_dir / "api.h"
    api_text = api_h.read_text()
    api_text = subst_once(api_text, "CRYPTO_PUBLICKEYBYTES", pk_b)
    api_text = subst_once(api_text, "CRYPTO_SECRETKEYBYTES", sk_b)
    api_text = subst_once(api_text, "CRYPTO_CIPHERTEXTBYTES", ct_b)
    api_h.write_text(api_text)

    # crypto_kem_mceliece348864.h — namespaced mirrors of the same constants.
    namespaced = ref_dir / "crypto_kem_mceliece348864.h"
    nstext = namespaced.read_text()
    nstext = subst_once(nstext, "crypto_kem_mceliece348864_ref_PUBLICKEYBYTES", pk_b)
    nstext = subst_once(nstext, "crypto_kem_mceliece348864_ref_SECRETKEYBYTES", sk_b)
    nstext = subst_once(nstext, "crypto_kem_mceliece348864_ref_CIPHERTEXTBYTES", ct_b)
    namespaced.write_text(nstext)


if __name__ == "__main__":
    main()
