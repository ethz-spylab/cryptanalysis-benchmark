#!/usr/bin/env python3
"""
Scale-down patcher for the pqNTRUsign (Gaussian-1024) MEDIUM band (N=384).

Unlike the easy/hard bands (patch_pqntrusign.py), the medium ring degree
N = 384 is NOT a power of two. With q = 65537 = 2^16 + 1 the negacyclic NTT
exists only when 2N | 2^16, i.e. only for power-of-two N, so the reference
keygen's NTT-based division h = g/(p*f) mod (x^N+1, q) has no usable
root-of-unity tables here.

This patcher therefore:
  * sets N=384, N_bits=ceil(log2 N), padded_N=384 and the product-form weight d
    in common/param.c (the precomputed roots1024/invntt1024 tables are left in
    place but become dead code -- the NTT/Inv_NTT routines are no longer called);
  * replaces the NTT-based key-division in common/pqNTRUSign.c::keygen with a
    SCHOOLBOOK NEGACYCLIC ring division: it builds the multiplication-by-(p*f)
    matrix over Z_q (q prime => field) and solves (p*f)*h == g by Gaussian
    elimination mod q. This needs no 2N-th roots, so N=384 works, and q stays
    65537 so every signature/rejection bound remains valid. The signing and
    verification ring multiplies already use the schoolbook/Karatsuba path
    (pol_mul_coefficients / pol_mul_mod_p), which works for any N -- only keygen
    depended on the NTT;
  * recomputes the hardcoded key/signature byte sizes in api.h from the packing
    formulas (identical to the easy/hard patcher).

Constraints:
  * pol_gen_flat needs 2*d+1 nonzero coefficients to fit in N, i.e. 2*d+1 <= N.
    For N=384 this means d <= 191.

Usage:
  patch_pqntrusign_medium.py <ReferenceImplementationRoot> <N> <d>
"""

import re
import sys


# ---------------------------------------------------------------------------
# C helper: schoolbook negacyclic ring division (q prime), inserted into keygen.
# ---------------------------------------------------------------------------
RING_DIV_HELPER = r"""
/*
 * Schoolbook negacyclic ring division for non-power-of-two ring degree.
 *
 * q = 65537 admits a negacyclic NTT only when 2N | 2^16 (power-of-two N), so
 * for this reduced degree the NTT-based key division is unavailable. Instead we
 * solve  (af) * h == g  in  Z_q[x]/(x^N+1)  directly: q is prime, so Z_q is a
 * field, the multiplication-by-(af) map is a linear map whose matrix is the
 * skew-circulant (negacyclic) matrix of af, and h is recovered by Gaussian
 * elimination mod q. Returns 0 on success, -1 if af is not invertible (the
 * matrix is singular), in which case the caller regenerates the secret key.
 *
 * af must already be reduced into [0, q). h is centred to (-q/2, q/2], matching
 * the original Inv_NTT output.
 */
static int
schoolbook_ring_div(
          int64_t      *h,        /* out - g * af^{-1} mod (x^N+1, q), centred */
    const int64_t      *af,       /*  in - the multiplier (= p*f), in [0,q)    */
    const int64_t      *g,        /*  in - the dividend                        */
    const PQ_PARAM_SET *param)
{
    const int64_t q = param->q;
    const int     N = (int)param->N;
    const int     W = N + 1;       /* augmented width: N coeffs + the g column */
    int     i, j, k, col, piv;
    int64_t *M = (int64_t *) malloc(sizeof(int64_t) * (size_t)N * (size_t)W);
    if (M == NULL)
    {
        printf("schoolbook_ring_div: malloc failed\n");
        exit(1);
    }

    /* Row k, column j of the multiplication-by-af matrix:
     *   (af*h)_k = sum_j s(k,j) * af[(k-j) mod N] * h[j],
     * with s = +1 when k >= j and -1 otherwise (because x^N = -1).
     * Augmented column N holds g. */
    for (k = 0; k < N; k++)
    {
        for (j = 0; j < N; j++)
        {
            int     dd = k - j;
            int64_t c;
            if (dd >= 0)
                c = af[dd] % q;
            else
                c = (q - af[dd + N] % q) % q;
            M[k * W + j] = ((c % q) + q) % q;
        }
        M[k * W + N] = ((g[k] % q) + q) % q;
    }

    /* Gauss-Jordan elimination over Z_q. */
    for (col = 0; col < N; col++)
    {
        piv = -1;
        for (i = col; i < N; i++)
        {
            if (M[i * W + col] != 0)
            {
                piv = i;
                break;
            }
        }
        if (piv < 0)              /* singular: af has no inverse in the ring */
        {
            free(M);
            return -1;
        }
        if (piv != col)
        {
            for (j = col; j < W; j++)
            {
                int64_t t      = M[col * W + j];
                M[col * W + j] = M[piv * W + j];
                M[piv * W + j] = t;
            }
        }
        {
            int64_t inv = InvMod(M[col * W + col], q);
            for (j = col; j < W; j++)
                M[col * W + j] = M[col * W + j] * inv % q;
        }
        for (i = 0; i < N; i++)
        {
            int64_t factor;
            if (i == col)
                continue;
            factor = M[i * W + col];
            if (factor == 0)
                continue;
            for (j = col; j < W; j++)
            {
                int64_t v = M[i * W + j] - factor * M[col * W + j] % q;
                M[i * W + j] = ((v % q) + q) % q;
            }
        }
    }

    for (i = 0; i < N; i++)
    {
        int64_t v = M[i * W + N];
        if (v > q / 2)
            v -= q;
        h[i] = v;
    }

    free(M);
    return 0;
}

"""


# New keygen body that uses the schoolbook division instead of the NTT path.
NEW_KEYGEN_BODY = r"""    memset(buf, 0, sizeof(int64_t)*param->padded_N*4);
    (void) fntt; (void) gntt; (void) hntt;  /* NTT scratch unused for this degree */

    /*
     * Non-power-of-two ring degree: q=65537 admits no negacyclic NTT here, so
     * h = g/(p*f) mod (x^N+1, q) is computed with a schoolbook ring division
     * (Gaussian elimination mod q) instead of the NTT path. The arithmetic is
     * identical; only the multiply/divide implementation differs. f is
     * regenerated if p*f happens to be non-invertible in the ring.
     */
    flag = 0;
    while (flag != 1)
    {
        flag = 1;

        do {
            pol_gen_flat(f, param->N, param->d);
        }while (normf(f, param)>param->B_k);
        /* set tmp = p*f, reduced into [0, q) */
        for (i=0;i<param->N;i++)
        {
            int64_t c = (2*f[i]) % param->q;
            if (c<0)
                c += param->q;
            tmp[i] = c;
        }

        do{
            do{
                pol_gen_flat(g, param->N, param->d);
            }while (normf(g, param)>param->B_k);
        }while (pol_inv_mod2(g_inv, g, param->N) == -1);

        /* h = g * (p*f)^{-1} mod (x^N+1, q); regenerate the key if singular */
        if (schoolbook_ring_div(h, tmp, g, param) != 0)
            flag = 0;
    }"""


def patch_param_c(path, N, d):
    src = open(path).read()
    nbits = (N - 1).bit_length()  # ceil(log2 N)

    src, n = re.subn(r"\b10,(\s*/\* bitlength of N \*/)", f"{nbits},\\1", src)
    assert n >= 1, "N_bits field not found"
    src, n = re.subn(r"\b1024,(\s*/\* ring degree \*/)", f"{N},\\1", src)
    assert n >= 1, "ring degree field not found"
    src, n = re.subn(
        r"\b1024,(\s*/\* # Polynomial coefficients for Karatsuba \*/)",
        f"{N},\\1",
        src,
    )
    assert n >= 1, "padded_N field not found"
    src, n = re.subn(
        r"\b205,(\s*/\* Product form \+1/-1 counts \*/)",
        f"{d},\\1",
        src,
    )
    assert n >= 1, "product-form d field not found"

    open(path, "w").write(src)
    print(
        f"[param.c] N={N} N_bits={nbits} padded_N={N} d={d} "
        f"(NTT tables left as dead code)"
    )


def patch_keygen_c(path):
    src = open(path).read()

    # 1) Insert the schoolbook ring-division helper just before keygen().
    anchor = "void keygen(\n            int64_t     *f,"
    assert src.count(anchor) == 1, "keygen() anchor not found exactly once"
    src = src.replace(anchor, RING_DIV_HELPER + anchor, 1)

    # 2) Replace the NTT-based key-division body with the schoolbook version.
    start_tok = "    memset(buf, 0, sizeof(int64_t)*param->padded_N*4);"
    end_tok = "    Inv_NTT(param, h, hntt);"
    s = src.index(start_tok)
    e = src.index(end_tok, s)
    assert src.count(start_tok) == 1, "keygen body start anchor not unique"
    assert src.count(end_tok) == 1, "keygen body end anchor not unique"
    src = src[:s] + NEW_KEYGEN_BODY + src[e + len(end_tok) :]

    open(path, "w").write(src)
    print("[pqNTRUSign.c] keygen now uses schoolbook negacyclic ring division")


def patch_api_h(path, N):
    pk = 2 * N + 17  # 1 + (N+8)*2
    sk = (N // 5) * 2 + 4 + N // 8 + (N + 8) * 2
    src = open(path).read()
    for macro, val in (
        ("CRYPTO_SECRETKEYBYTES", sk),
        ("CRYPTO_PUBLICKEYBYTES", pk),
        ("CRYPTO_BYTES", pk),
    ):
        src, n = re.subn(rf"(#define {macro}\s+)\d+", rf"\g<1>{val}", src)
        assert n == 1, f"{macro} replaced {n} times (expected 1)"
    open(path, "w").write(src)
    print(f"[api.h] CRYPTO_PUBLICKEYBYTES=CRYPTO_BYTES={pk} CRYPTO_SECRETKEYBYTES={sk}")


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: patch_pqntrusign_medium.py <RefImplRoot> <N> <d>")
    ref = sys.argv[1].rstrip("/")
    N = int(sys.argv[2])
    d = int(sys.argv[3])
    if 2 * d + 1 > N:
        sys.exit(f"infeasible d={d}: need 2d+1 <= N={N}")
    patch_param_c(f"{ref}/common/param.c", N, d)
    patch_keygen_c(f"{ref}/common/pqNTRUSign.c")
    patch_api_h(f"{ref}/Gaussian-1024/api.h", N)


if __name__ == "__main__":
    main()
