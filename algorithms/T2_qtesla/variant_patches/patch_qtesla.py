#!/usr/bin/env python3
"""Weaken a freshly-extracted qTesla_I Reference tree to a reduced ring
dimension n (and, for the Medium band, a paired modulus q) per
algorithm_scaling_down/nist_pqc/qtesla.txt.

Usage:
    patch_qtesla.py <qtesla_I_dir> <PARAM_N> <PARAM_Q> [widen]

  <qtesla_I_dir> is the directory holding params.h / consts.c / gauss.h, i.e.
  .../NIST_submission_round2_Mar2019/Reference_implementation/qTesla_I

  The optional 4th argument "widen" (any truthy token, e.g. "1" / "widen")
  ADDITIONALLY rewrites poly.c so the negacyclic NTT / poly_mul stay correct for
  a larger modulus q (~2^26).  The -D_qTESLA_I_ build path (which build_cli.sh
  MUST keep) accumulates the forward / inverse NTT butterflies UNREDUCED in the
  int32 `poly` storage and overflows for q > ~2^22.9.  The widen mode ports the
  Barrett-reduction style the larger qTESLA sets (III / V) use into the I-path:
  it enables qTESLA's own `barr_reduce` for the I build and inserts it after
  every butterfly add/sub in ntt() and nttinv(), so coefficients stay reduced
  mod q (|coeff| < ~2q < 2^27) at every stage instead of growing to ~145*q.
  Barrett reduction is value-preserving mod q and the NTT is linear mod q, so
  the output coefficients are bit-identical (mod q) to what the reference would
  compute if int32 never overflowed -- only the intermediate magnitudes change.
  This is used ONLY for the Medium band; easy/hard pass no 4th arg and poly.c is
  left pristine.

Reducing PARAM_N is NOT a one-line change.  This patcher performs the full
coordinated edit the proposal calls for:

  1. params.h  - PARAM_N, PARAM_N_LOG, and (for a q change) PARAM_Q,
     PARAM_Q_LOG, PARAM_QINV, PARAM_BARR_MULT, PARAM_BARR_DIV, PARAM_R; plus the
     Montgomery normaliser PARAM_R2_INVN = R^2 * n^{-1} mod q for every band.
  2. consts.c  - regenerates the size-n negacyclic-NTT twiddle tables
     `zeta` / `zetainv` as the 2n-th roots of unity mod q, in the EXACT
     index ordering the reference ntt()/nttinv() loops in poly.c consume:
         zeta[i]    = psi^{ brv_logn((i+1) mod n) }        * R mod q
         zetainv[i] = psi^{ (-1 - brv_logn(i)) mod 2n }    * R mod q
     where psi is a primitive 2n-th root of unity mod q and brv_logn is the
     bit-reversal over log2(n) bits.  These formulas were reverse-engineered
     from, and verified byte-identical against, the shipped n=512 tables; any
     primitive 2n-th root yields a self-consistent correct transform because the
     public polynomial `a` is sampled directly in the NTT/frequency domain
     (poly_uniform), so the protocol never pins a specific root ordering.
  3. gauss.h  - CHUNK_SIZE is lowered from 512 to n, because kmxGauss() writes
     CHUNK_SIZE samples into the poly z[PARAM_N] buffer; leaving it at 512 would
     overflow that buffer for n < 512.

Every substitution must hit exactly the expected number of times, otherwise we
abort loudly so generation can never silently emit an unweakened / mismatched
variant.
"""

import pathlib
import re
import sys


def brv(x, bits):
    r = 0
    for i in range(bits):
        r = (r << 1) | ((x >> i) & 1)
    return r


def find_psi(q, n):
    """Return a primitive 2n-th root of unity mod q (q prime, 2n | q-1)."""
    qm1 = q - 1
    if qm1 % (2 * n) != 0:
        raise SystemExit(f"q-1 not divisible by 2n: q={q} n={n}")
    # factor q-1
    factors = set()
    m = qm1
    d = 2
    while d * d <= m:
        while m % d == 0:
            factors.add(d)
            m //= d
        d += 1
    if m > 1:
        factors.add(m)

    def is_generator(g):
        return all(pow(g, qm1 // p, q) != 1 for p in factors)

    g = 2
    while not is_generator(g):
        g += 1
    psi = pow(g, qm1 // (2 * n), q)
    if pow(psi, 2 * n, q) != 1 or pow(psi, n, q) != q - 1:
        raise SystemExit("internal error: psi is not a primitive 2n-th root")
    return psi


def gen_tables(n, q):
    logn = n.bit_length() - 1
    if (1 << logn) != n:
        raise SystemExit(f"PARAM_N must be a power of two, got {n}")
    R = (1 << 32) % q
    psi = find_psi(q, n)
    zeta = [(pow(psi, brv((i + 1) % n, logn), q) * R) % q for i in range(n)]
    zetainv = [(pow(psi, (-1 - brv(i, logn)) % (2 * n), q) * R) % q for i in range(n)]
    return zeta, zetainv


def fmt_array(name, vals):
    lines = []
    for i in range(0, len(vals), 16):
        lines.append(", ".join(str(v) for v in vals[i : i + 16]) + ", ")
    body = "\n".join(lines)
    return f"poly {name} = {{\n\n{body}\n}};"


def subst_once(text, key, val, count=1):
    new, n = re.subn(rf"#define\s+{re.escape(key)}\s+\S+", f"#define {key} {val}", text)
    if n != count:
        raise SystemExit(
            f"params.h: expected {count} substitution(s) of {key}, made {n}"
        )
    return new


def widen_poly_c(ref):
    """Port qTESLA III/V Barrett reduction into the -D_qTESLA_I_ NTT so a larger
    modulus q (~2^26) cannot overflow the int32 `poly` accumulators.  Three exact
    edits to poly.c, each asserted to hit exactly once."""
    poly_path = ref / "poly.c"
    src = poly_path.read_text()

    edits = [
        # 1) compile barr_reduce for the I build (it ships guarded out for I)
        (
            "#if !defined(_qTESLA_I_)\n\n"
            "int32_t barr_reduce(int32_t a)\n"
            "{ // Barrett reduction\n"
            "  int32_t u = ((int64_t)a*PARAM_BARR_MULT)>>PARAM_BARR_DIV;\n"
            "  return a - (int32_t)u*PARAM_Q;\n"
            "}\n\n"
            "#endif",
            "int32_t barr_reduce(int32_t a)\n"
            "{ // Barrett reduction (enabled for the widened large-q I build)\n"
            "  int32_t u = ((int64_t)a*PARAM_BARR_MULT)>>PARAM_BARR_DIV;\n"
            "  return a - (int32_t)u*PARAM_Q;\n"
            "}",
        ),
        # 2) forward ntt butterfly: reduce both outputs every stage
        (
            "        int32_t temp = reduce((int64_t)W * a[j+NumoProblems]);\n"
            "        a[j + NumoProblems] = a[j] - temp;\n"
            "        a[j] = temp + a[j];",
            "        int32_t temp = reduce((int64_t)W * a[j+NumoProblems]);\n"
            "        a[j + NumoProblems] = barr_reduce(a[j] - temp);\n"
            "        a[j] = barr_reduce(temp + a[j]);",
        ),
        # 3) inverse ntt I-path add: reduce every stage (mirrors III/V)
        (
            "#if defined(_qTESLA_I_)\n"
            "        a[j] = temp + a[j + NumoProblems];\n"
            "#else",
            "#if defined(_qTESLA_I_)\n"
            "        a[j] = barr_reduce(temp + a[j + NumoProblems]);\n"
            "#else",
        ),
    ]
    for old, new in edits:
        cnt = src.count(old)
        if cnt != 1:
            raise SystemExit(f"poly.c widen: expected 1 match for an edit, got {cnt}")
        src = src.replace(old, new)
    poly_path.write_text(src)


def main():
    if len(sys.argv) not in (4, 5):
        raise SystemExit(__doc__)
    ref = pathlib.Path(sys.argv[1])
    n = int(sys.argv[2])
    q = int(sys.argv[3])
    widen = len(sys.argv) == 5 and sys.argv[4] not in ("", "0")
    logn = n.bit_length() - 1
    q_log = q.bit_length()  # q < 2^q_log, so coeffs fit in q_log bits
    if q >= (1 << q_log):
        raise SystemExit("internal error computing PARAM_Q_LOG")
    R = (1 << 32) % q
    qinv = (-pow(q, -1, 1 << 32)) % (1 << 32)
    r2_invn = (R * R % q) * pow(n, -1, q) % q
    barr_div = 32
    barr_mult = round((1 << barr_div) / q)

    # --- params.h --------------------------------------------------------
    params_path = ref / "params.h"
    p = params_path.read_text()
    p = subst_once(p, "PARAM_N", n)
    p = subst_once(p, "PARAM_N_LOG", logn)
    p = subst_once(p, "PARAM_Q", q)
    p = subst_once(p, "PARAM_Q_LOG", q_log)
    p = subst_once(p, "PARAM_QINV", qinv)
    p = subst_once(p, "PARAM_BARR_MULT", barr_mult)
    p = subst_once(p, "PARAM_BARR_DIV", barr_div)
    p = subst_once(p, "PARAM_R", R)
    p = subst_once(p, "PARAM_R2_INVN", r2_invn)
    params_path.write_text(p)

    # --- consts.c : regenerate the NTT twiddle tables --------------------
    consts_path = ref / "consts.c"
    c = consts_path.read_text()
    zeta, zetainv = gen_tables(n, q)
    c, nz = re.subn(
        r"poly\s+zeta\s*=\s*\{.*?\};", fmt_array("zeta", zeta), c, count=1, flags=re.S
    )
    c, ni = re.subn(
        r"poly\s+zetainv\s*=\s*\{.*?\};",
        fmt_array("zetainv", zetainv),
        c,
        count=1,
        flags=re.S,
    )
    if nz != 1 or ni != 1:
        raise SystemExit(
            f"consts.c: expected to rewrite zeta/zetainv once "
            f"each, got zeta={nz} zetainv={ni}"
        )
    consts_path.write_text(c)

    # --- gauss.h : shrink CHUNK_SIZE so kmxGauss does not overflow z -----
    gauss_path = ref / "gauss.h"
    g = gauss_path.read_text()
    g, ng = re.subn(
        r"#define\s+CHUNK_SIZE\s+\d+", f"#define CHUNK_SIZE {n}", g, count=1
    )
    if ng != 1:
        raise SystemExit(f"gauss.h: expected 1 CHUNK_SIZE substitution, got {ng}")
    gauss_path.write_text(g)

    # --- poly.c : widen NTT (Barrett every stage) for large q ------------
    if widen:
        widen_poly_c(ref)

    print(
        f"patched qTesla_I -> n={n} (N_LOG={logn}) q={q} (Q_LOG={q_log}) "
        f"R={R} QINV={qinv} R2_INVN={r2_invn} BARR_MULT={barr_mult} "
        f"CHUNK_SIZE={n}; regenerated zeta/zetainv ({len(zeta)} entries each)"
        f"{'; widened poly.c NTT (Barrett per-stage)' if widen else ''}"
    )


if __name__ == "__main__":
    main()
