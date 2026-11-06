#!/usr/bin/env python3
"""
Titanium_CCA_std scaling-down patcher (concealment design).

Reduces the MP-LWE degree N and, because Titanium's two N-dependent exact NTTs
have transform lengths L_NK = N+K+1 and L_NDK = N+D+K+1 that must BOTH divide
Q-1 (impossible for any reduced N at the shipped Q=118273), simultaneously moves
to a new prime modulus Q' chosen so that

    768 (=D+K+1) | Q'-1 ,  (N+K+1) | Q'-1 ,  (N+D+K+1) | Q'-1 .

Q' is kept inside (2^16, 2^17) so Q_BITS stays 17 and the fully-unrolled 17-bit
bit-packing in pack.c (and the Q_BITS-derived pk/sk byte sizes in api.h) remain
valid; only CRYPTO_CIPHERTEXTBYTES (which depends on N) is updated.

All omega twiddle tables are regenerated as the appropriate roots of unity mod
Q' for the new transform lengths.  The generator is validated elsewhere to
reproduce the shipped (N=1024, Q=118273) tables byte-for-byte.

K and D are held fixed (only N and Q' move per band).

Usage: patch_titanium.py <CCA_std_src_dir> <N> <Q>
"""

import re
import sys

K = 511
D = 256
Q_BITS = 17  # unchanged: requires 2^16 < Q' < 2^17
C2_COMPRESSION_BYTE = 1
HASH_LENGTH = 32  # KEM confirmation tag appended to the ciphertext


def factor(n):
    f = set()
    d = 2
    while d * d <= n:
        while n % d == 0:
            f.add(d)
            n //= d
        d += 1
    if n > 1:
        f.add(n)
    return f


def smallest_primitive_root(q):
    facs = factor(q - 1)
    for g in range(2, q):
        if all(pow(g, (q - 1) // p, q) != 1 for p in facs):
            return g
    raise RuntimeError("no primitive root found")


def gen_table(L, Q, gamma0):
    """omega (g^i) and omega_inv (g^-i) for a primitive L-th root g."""
    assert (Q - 1) % L == 0, f"L={L} does not divide Q-1={Q - 1}"
    g = pow(gamma0, (Q - 1) // L, Q)
    # sanity: g must be a *primitive* L-th root of unity
    assert pow(g, L, Q) == 1
    for p in factor(L):
        assert pow(g, L // p, Q) != 1, f"g not primitive {L}-th root"
    fwd = [pow(g, i, Q) for i in range(L)]
    ginv = pow(g, -1, Q)
    inv = [pow(ginv, i, Q) for i in range(L)]
    return fwd, inv


def fmt_table(name, vals):
    body = ",".join(str(v) for v in vals)
    return f"static const uint32_t {name}[{len(vals)}]={{{body}}};\n"


NTT_CORE = r"""
/* Partial NTT (naive O(n^2) method with Hornor's rule) */
static void ntt_core(uint32_t *a, uint32_t N1, uint32_t N2, uint32_t DIM, const uint32_t *omega_n)
{
	uint32_t DIM_NTT = N1 * N2;
	uint32_t b[N + D + K + 1];
	int i, j;

	b[0] = 0;
	for (i = DIM - 1; i >= 0; i--)
	{
		b[0] = (b[0] + a[i]) % Q;
	}

	for (i = 1; i < DIM_NTT; i++)
	{
		b[i] = 0;
		/* Hornor's rule */
		for (j = DIM - 1; j >= 0; j--)
		{
			b[i] = (((uint64_t)b[i] * (uint64_t)omega_n[i]) % Q) + a[j];
		}
		b[i] %= Q;
	}

	/* change the order to match the optimized NTT */
	for (i = 0; i < DIM_NTT; i++)
	{
		a[i] = b[(i % N2) * N1 + i / N2];
	}
}

/* Partial INTT (naive O(n^2) method with Hornor's rule) */
static void intt_core(uint32_t *a, uint32_t N1, uint32_t N2, uint32_t DIM, const uint32_t *omega_n, uint32_t inv_n)
{
	uint32_t DIM_NTT = N1 * N2;
	uint32_t b[N + D + K + 1];
	int i, j;

	/* change the order to match the optimized NTT */
	for (i = 0; i < DIM_NTT; i++)
	{
		b[i] = a[(i % N1) * N2 + i / N1];
	}

	a[0] = 0;
	for (i = DIM_NTT - 1; i >= 0; i--)
	{
		a[0] = (a[0] + b[i]) % Q;
	}
	a[0] = ((uint64_t)a[0] * (uint64_t)inv_n) % Q;

	for (i = 1; i < DIM; i++)
	{
		a[i] = 0;
		/* Hornor's rule */
		for (j = DIM_NTT - 1; j >= 0; j--)
		{
			a[i] = (((uint64_t)a[i] * (uint64_t)omega_n[i]) % Q) + b[j];
		}
		a[i] = ((uint64_t)a[i] * (uint64_t)inv_n) % Q;
	}
}
"""


def build_ntt_c(N, Q, gamma0):
    Lndk = N + D + K + 1
    Lnk = N + K + 1
    Ldk = D + K + 1  # 768, fixed
    assert Ldk == 768

    # Lndk is always strictly the largest. Lnk and Ldk collide iff N == D
    # (e.g. the N=256 easy band): they then share an identical omega table of
    # length 768, so every table/#define is emitted once per DISTINCT length.
    fwd_lengths = sorted({Ldk, Lnk, Lndk})  # forward table needed for all three
    inv_lengths = sorted({Ldk, Lnk})  # inverse table needed for NK and DK

    out = []
    out.append(
        "/* ****************************** *\n"
        " * Titanium_CCA_std (scaled)      *\n"
        " * NTT functions (regenerated)    *\n"
        " * ****************************** */\n\n"
    )
    out.append('#include "param.h"\n#include "ntt.h"\n#include <stdint.h>\n\n')

    # mixed-radix factors: N1=1, N2=L => identity permutation, pure DFT/IDFT.
    for L in fwd_lengths:
        out.append(f"#define N1_{L} 1\n#define N2_{L} {L}\n")
    out.append("\n")
    for L in fwd_lengths:
        out.append(f"#define INV_{L} {pow(L, -1, Q)}\n")
    out.append("\n")

    for L in fwd_lengths:
        fwd, inv = gen_table(L, Q, gamma0)
        out.append(fmt_table(f"omega_{L}", fwd))
        if L in inv_lengths:
            out.append(fmt_table(f"omega_{L}_inv", inv))
    out.append("\n")

    out.append(NTT_CORE)
    out.append("\n")

    out.append(
        f"void intt_{Lndk}_{Lndk}(uint32_t *a)\n{{\n"
        f"\tintt_core(a, N1_{Lndk}, N2_{Lndk}, {Lndk}, omega_{Lndk}, INV_{Lndk});\n}}\n\n"
    )
    out.append(
        f"void intt_{Ldk}_{Ldk}(uint32_t *a)\n{{\n"
        f"\tintt_core(a, N1_{Ldk}, N2_{Ldk}, {Ldk}, omega_{Ldk}, INV_{Ldk});\n}}\n\n"
    )
    out.append(
        f"void ntt_{Lnk}_{Lnk}(uint32_t *a)\n{{\n"
        f"\tntt_core(a, N1_{Lnk}, N2_{Lnk}, {Lnk}, omega_{Lnk});\n}}\n\n"
    )
    out.append(
        f"void intt_{Lnk}_{Lnk}_inv(uint32_t *a)\n{{\n"
        f"\tintt_core(a, N1_{Lnk}, N2_{Lnk}, {Lnk}, omega_{Lnk}_inv, INV_{Lnk});\n}}\n\n"
    )
    out.append(
        f"void ntt_{Ldk}_{Ldk}_inv(uint32_t *a)\n{{\n"
        f"\tntt_core(a, N1_{Ldk}, N2_{Ldk}, {Ldk}, omega_{Ldk}_inv);\n}}\n"
    )
    return "".join(out)


def build_ntt_h(N):
    Lndk = N + D + K + 1
    Lnk = N + K + 1
    Ldk = D + K + 1
    return (
        "#ifndef NTT_H\n#define NTT_H\n\n#include <stdint.h>\n\n"
        f"void intt_{Lndk}_{Lndk}(uint32_t *a);\n"
        f"void intt_{Ldk}_{Ldk}(uint32_t *a);\n"
        f"void ntt_{Lnk}_{Lnk}(uint32_t *a);\n"
        f"void intt_{Lnk}_{Lnk}_inv(uint32_t *a);\n"
        f"void ntt_{Ldk}_{Ldk}_inv(uint32_t *a);\n\n#endif\n"
    )


def patch_param_h(text, N, Q):
    Lndk = N + D + K + 1
    Lnk = N + K + 1
    Ldk = D + K + 1
    n_sub = 0

    def sub(pat, repl, t):
        nonlocal n_sub
        t2, c = re.subn(pat, repl, t)
        assert c >= 1, f"param.h: pattern not found: {pat}"
        n_sub += c
        return t2

    text = sub(r"#define\s+Q\s+118273\b", f"#define Q {Q}", text)
    text = sub(r"#define\s+N\s+1024\b", f"#define N {N}", text)
    text = sub(
        r"#define\s+INTT_NDK_NDK\s+intt_1792_1792\b",
        f"#define INTT_NDK_NDK intt_{Lndk}_{Lndk}",
        text,
    )
    text = sub(
        r"#define\s+INTT_DK_DK\s+intt_768_768\b",
        f"#define INTT_DK_DK intt_{Ldk}_{Ldk}",
        text,
    )
    text = sub(
        r"#define\s+NTT_NK_NK\s+ntt_1536_1536\b",
        f"#define NTT_NK_NK ntt_{Lnk}_{Lnk}",
        text,
    )
    text = sub(
        r"#define\s+INTT_NK_NK_INV\s+intt_1536_1536_inv\b",
        f"#define INTT_NK_NK_INV intt_{Lnk}_{Lnk}_inv",
        text,
    )
    text = sub(
        r"#define\s+NTT_DK_DK_INV\s+ntt_768_768_inv\b",
        f"#define NTT_DK_DK_INV ntt_{Ldk}_{Ldk}_inv",
        text,
    )
    # Q_BITS must stay 17.
    assert re.search(r"#define\s+Q_BITS\s+17\b", text), "Q_BITS != 17 unexpected"
    return text


def patch_api_h(text, N):
    ct = (N + K + 1) // 8 * Q_BITS + D * C2_COMPRESSION_BYTE + HASH_LENGTH
    text, c = re.subn(
        r"#define\s+CRYPTO_CIPHERTEXTBYTES\s+\d+",
        f"#define CRYPTO_CIPHERTEXTBYTES {ct}",
        text,
    )
    assert c == 1, "api.h CRYPTO_CIPHERTEXTBYTES not patched"
    return text


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: patch_titanium.py <src_dir> <N> <Q>")
    src = sys.argv[1]
    N = int(sys.argv[2])
    Q = int(sys.argv[3])

    # Hard invariants for a sound, non-UB scaled instance.
    assert N % 8 == 0, "N must be a multiple of 8 (8-coeff packing)"
    assert 1 << 16 < Q < 1 << 17, "Q' must lie in (2^16, 2^17) to keep Q_BITS=17"
    for L in (D + K + 1, N + K + 1, N + D + K + 1):
        assert (Q - 1) % L == 0, f"L={L} must divide Q-1 for an NTT to exist"

    gamma0 = smallest_primitive_root(Q)

    p = f"{src}/param.h"
    with open(p) as f:
        param = f.read()
    with open(p, "w") as f:
        f.write(patch_param_h(param, N, Q))

    a = f"{src}/api.h"
    with open(a) as f:
        api = f.read()
    with open(a, "w") as f:
        f.write(patch_api_h(api, N))

    with open(f"{src}/ntt.h", "w") as f:
        f.write(build_ntt_h(N))
    with open(f"{src}/ntt.c", "w") as f:
        f.write(build_ntt_c(N, Q, gamma0))

    print(
        f"[patch_titanium] N={N} Q={Q} gamma0={gamma0} "
        f"L_NK={N + K + 1} L_NDK={N + D + K + 1} "
        f"CIPHERTEXTBYTES={(N + K + 1) // 8 * Q_BITS + D + HASH_LENGTH}"
    )


if __name__ == "__main__":
    main()
