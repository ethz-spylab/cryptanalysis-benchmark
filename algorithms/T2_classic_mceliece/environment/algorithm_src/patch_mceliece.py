#!/usr/bin/env python3
"""Apply variant parameters to a freshly-extracted Classic McEliece
mceliece348864 reference tree.

Usage:
    patch_mceliece.py <ref_dir> <GFBITS> <SYS_N> <SYS_T> <MOD_POLY_BITS_HEX>

  MOD_POLY_BITS_HEX encodes the irreducible polynomial f(x) of degree GFBITS
  over GF(2) used to reduce field-multiplication results. Bits set in the
  hex value correspond to non-leading exponents.

      x^12 + x^3 + 1                       -> 0x9    (bits 3, 0)
      x^10 + x^3 + 1                       -> 0x9    (bits 3, 0)
      x^8  + x^4 + x^3 + x + 1             -> 0x1B   (bits 4, 3, 1, 0)

Edits:
  params.h                          — GFBITS, SYS_N, SYS_T.
  api.h                             — CRYPTO_*BYTES recomputed.
  crypto_kem_mceliece348864.h       — same constants for the namespaced API.
  gf.c                              — replaced with a parameterised reduction
                                      driven by GFBITS and MOD_POLY_BITS so
                                      the same code body is correct for any
                                      irreducible f(x) of degree m <= 16.

The Goppa-polynomial reduction in gf.c::GF_mul (shifts 3, 1, 0 plus mul-by-2)
implements g(z) = z^t + z^3 + z + 2; that polynomial structure is independent
of t, so changing SYS_T alone does not require touching GF_mul.
"""

import pathlib
import re
import sys


GF_C_TEMPLATE = r"""/*
  Variant-patched GF arithmetic for Classic McEliece.

  GF(2^{m}) with reduction polynomial f(x) whose non-leading exponent bitmap
  is MOD_POLY_BITS = {mod_poly_hex}.
*/

#include "gf.h"
#include "params.h"

#define MOD_POLY_BITS {mod_poly_hex}u

gf gf_iszero(gf a)
{{
    uint32_t t = a;
    t -= 1;
    t >>= 19;
    return (gf) t;
}}

gf gf_add(gf in0, gf in1)
{{
    return in0 ^ in1;
}}

static inline uint32_t gf_reduce(uint32_t tmp)
{{
    /* Iteratively reduce bits at positions [GFBITS, 2*GFBITS-2] modulo f(x).
       For each set bit at position k, x^k = x^(k-GFBITS) * sum(x^e), so we
       XOR the shifted MOD_POLY_BITS pattern into tmp and clear bit k. */
    int k;
    for (k = 2 * GFBITS - 2; k >= GFBITS; k--) {{
        uint32_t bit = (tmp >> k) & 1u;
        tmp ^= bit * (MOD_POLY_BITS << (k - GFBITS));
        tmp ^= bit << k;
    }}
    return tmp & ((1u << GFBITS) - 1);
}}

gf gf_mul(gf in0, gf in1)
{{
    int i;
    uint32_t tmp;
    uint32_t t0 = in0;
    uint32_t t1 = in1;

    tmp = t0 * (t1 & 1);
    for (i = 1; i < GFBITS; i++)
        tmp ^= (t0 * (t1 & (1u << i)));

    return (gf) gf_reduce(tmp);
}}

static inline gf gf_sq(gf in)
{{
    static const uint32_t B[] = {{0x55555555, 0x33333333, 0x0F0F0F0F, 0x00FF00FF}};

    uint32_t x = in;

    x = (x | (x << 8)) & B[3];
    x = (x | (x << 4)) & B[2];
    x = (x | (x << 2)) & B[1];
    x = (x | (x << 1)) & B[0];

    return (gf) gf_reduce(x);
}}

gf gf_inv(gf in)
{{
    /* Generic Fermat inverse: in^(2^m - 2) = product over i in [1, m-1] of
       in^(2^i). The chain in upstream's m=12 gf_inv is just a hand-unrolled
       version of this loop. */
    int i;
    gf temp = gf_sq(in);   /* in^2 */
    gf out = temp;
    for (i = 2; i < GFBITS; i++) {{
        temp = gf_sq(temp);    /* in^(2^i) */
        out = gf_mul(out, temp);
    }}
    return out;
}}

gf gf_frac(gf den, gf num)
{{
    return gf_mul(gf_inv(den), num);
}}

/* Reduce mod g(z) = z^SYS_T + z^3 + z + 2. The shifts and the gf 2 constant
   are intrinsic to that polynomial shape; they are independent of SYS_T,
   so we leave the upstream GF_mul body byte-identical to the original. */
void GF_mul(gf *out, gf *in0, gf *in1)
{{
    int i, j;

    gf prod[ SYS_T*2-1 ];

    for (i = 0; i < SYS_T*2-1; i++)
        prod[i] = 0;

    for (i = 0; i < SYS_T; i++)
        for (j = 0; j < SYS_T; j++)
            prod[i+j] ^= gf_mul(in0[i], in1[j]);

    for (i = (SYS_T-1)*2; i >= SYS_T; i--)
    {{
        prod[i - SYS_T + 3] ^= prod[i];
        prod[i - SYS_T + 1] ^= prod[i];
        prod[i - SYS_T + 0] ^= gf_mul(prod[i], (gf) 2);
    }}

    for (i = 0; i < SYS_T; i++)
        out[i] = prod[i];
}}
"""


def kem_byte_sizes(gfbits, sys_n, sys_t):
    irr_bytes = sys_t * 2
    cond_bytes = (1 << (gfbits - 4)) * (2 * gfbits - 1)
    pk_nrows = sys_t * gfbits
    pk_ncols = sys_n - pk_nrows
    pk_row_bytes = (pk_ncols + 7) // 8
    public_key_bytes = pk_nrows * pk_row_bytes
    secret_key_bytes = 40 + irr_bytes + cond_bytes + sys_n // 8
    synd_bytes = (pk_nrows + 7) // 8
    ciphertext_bytes = synd_bytes
    return public_key_bytes, secret_key_bytes, ciphertext_bytes


def main():
    ref_dir = pathlib.Path(sys.argv[1])
    gfbits = int(sys.argv[2])
    sys_n = int(sys.argv[3])
    sys_t = int(sys.argv[4])
    mod_poly_hex = sys.argv[5]

    if sys_n % 8 != 0:
        raise SystemExit(f"patch_mceliece.py: SYS_N={sys_n} must be a multiple of 8")
    if sys_n > (1 << gfbits):
        raise SystemExit(
            f"patch_mceliece.py: SYS_N={sys_n} cannot exceed 2^GFBITS={1 << gfbits}"
        )

    pk_b, sk_b, ct_b = kem_byte_sizes(gfbits, sys_n, sys_t)

    # params.h
    params_h = ref_dir / "params.h"
    text = params_h.read_text()
    for key, val in (("GFBITS", gfbits), ("SYS_N", sys_n), ("SYS_T", sys_t)):
        text, n = re.subn(rf"#define\s+{key}\s+\d+", f"#define {key} {val}", text)
        if n != 1:
            raise SystemExit(f"patch_mceliece.py: {key} not found in params.h")
    params_h.write_text(text)

    # api.h
    api_h = ref_dir / "api.h"
    api_text = api_h.read_text()
    api_subs = {
        "CRYPTO_PUBLICKEYBYTES": pk_b,
        "CRYPTO_SECRETKEYBYTES": sk_b,
        "CRYPTO_CIPHERTEXTBYTES": ct_b,
    }
    for key, val in api_subs.items():
        api_text, n = re.subn(
            rf"#define\s+{key}\s+\d+", f"#define {key} {val}", api_text
        )
        if n != 1:
            raise SystemExit(f"patch_mceliece.py: {key} not found in api.h")
    api_h.write_text(api_text)

    # crypto_kem_mceliece348864.h — namespaced mirrors of the same constants.
    namespaced = ref_dir / "crypto_kem_mceliece348864.h"
    nstext = namespaced.read_text()
    namespaced_subs = {
        "crypto_kem_mceliece348864_ref_PUBLICKEYBYTES": pk_b,
        "crypto_kem_mceliece348864_ref_SECRETKEYBYTES": sk_b,
        "crypto_kem_mceliece348864_ref_CIPHERTEXTBYTES": ct_b,
    }
    for key, val in namespaced_subs.items():
        nstext, n = re.subn(rf"#define\s+{key}\s+\d+", f"#define {key} {val}", nstext)
        if n != 1:
            raise SystemExit(
                f"patch_mceliece.py: {key} not found in crypto_kem_mceliece348864.h"
            )
    namespaced.write_text(nstext)

    # gf.c — replaced with a parameterised reduction driven by MOD_POLY_BITS.
    (ref_dir / "gf.c").write_text(
        GF_C_TEMPLATE.format(m=gfbits, mod_poly_hex=mod_poly_hex)
    )


if __name__ == "__main__":
    main()
