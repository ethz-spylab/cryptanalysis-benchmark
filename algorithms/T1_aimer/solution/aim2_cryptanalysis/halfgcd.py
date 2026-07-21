"""
This module contains division-related methods for univariate polynomials,
implemented using fast multiplication (FAFFT). Note that Rust impl.
does NOT use FAFFT automatically for such operations and is thus slower.
"""

import operator

FA = None


def set_FAFFT(FAFFT):
    global FA
    FA = FAFFT


def PolyGCD(a0, a1, Rx, destroy=False):
    """GCD(a0, a1)"""
    _, r = PolyQuoRem(a0, a1, Rx=Rx)
    if r.is_zero():
        return a1

    # a0 = r ?
    if a1.degree() > a0.degree():
        a0, a1 = a1, a0
    R = PolyHalfGCD(a0, a1, Rx=Rx)

    b0 = R[0] * a0 + R[1] * a1
    b1 = R[2] * a0 + R[3] * a1
    del R
    if destroy and len({id(b0), id(b1), id(a0), id(a1)}) == 4:
        a0.resize(0)
        a1.resize(0)
        del a0, a1
    if b1.is_zero():
        return b0
    _, r = PolyQuoRem(b0, b1, Rx=Rx)
    if r.is_zero():
        return b1
    c = r
    del _, r, b0
    return PolyGCD(b1, c, Rx=Rx, destroy=True)


def PolyHalfGCD(a0, a1, Rx, depth=0, destroy=False):
    """Matrix M=(qA, qB, qC, qD) s.t. M*(a0,a1) = half reduced polynomials"""
    if FA:
        mul = FA.multiply_auto
    else:
        mul = operator.mul

    assert depth < 40
    if a1.degree() <= a0.degree() // 2:
        try:
            return [Rx.constant(i) for i in (1, 0, 0, 1)]
        except AttributeError:
            return [Rx(i) for i in (1, 0, 0, 1)]

    m = (a0.degree() + 1) // 2
    b0 = Rx(a0.list()[m:])
    b1 = Rx(a1.list()[m:])
    R00, R01, R10, R11 = PolyHalfGCD(b0, b1, Rx=Rx, depth=depth + 1)
    del b0, b1

    # d = R00 * a0 + R01 * a1
    # e = R10 * a0 + R11 * a1
    d = mul(R00, a0) + mul(R01, a1)
    e = mul(R10, a0) + mul(R11, a1)
    if destroy and len({id(e), id(d), id(a0), id(a1)}) == 4:
        try:
            a0.resize(0)
            a1.resize(0)
        except AttributeError:
            pass
        del a0, a1
    if e.degree() < m:
        return R00, R01, R10, R11

    # q, f = d.PolyQuoRem(e)
    if FA:
        q, f = PolyQuoRem(d, e, Rx=Rx)
    else:
        q, f = divmod(d, e)  # (d // e, d % e)
    # assert q * e + f == d

    g0 = Rx(e.list()[m // 2 :])
    g1 = Rx(f.list()[m // 2 :])
    S00, S01, S10, S11 = PolyHalfGCD(g0, g1, Rx=Rx, depth=depth + 1, destroy=True)
    del g0, g1
    s00q01 = S00 + mul(q, S01)
    s10q11 = S10 + mul(q, S11)

    return (
        # +-
        # S01 * R00 + (S00 + q * S01) * R10,
        # S01 * R01 + (S00 + q * S01) * R11,
        # S11 * R00 + (S10 + q * S11) * R10,
        # S11 * R01 + (S10 + q * S11) * R11,
        mul(S01, R00) + mul(s00q01, R10),
        mul(S01, R01) + mul(s00q01, R11),
        mul(S11, R00) + mul(s10q11, R10),
        mul(S11, R01) + mul(s10q11, R11),
    )


def PolyQuoRem(f, g, Rx):
    """(q,r) in f = g*q + r"""
    m = f.degree()
    n = g.degree()
    if m < n:
        return Rx.constant(0), f
    elif m == n:
        c = f.lc() / g.lc()
        return Rx.constant(c), f - c * g
    assert m > n
    q = PolyQuo(f, g, Rx=Rx)
    # r = f - q * g
    r = f - FA.multiply_auto(q, g)
    assert q.degree() == m - n
    assert r.degree() < n
    return q, r


def PolyQuo(f, g, Rx):
    """f//g"""
    m = f.degree()
    n = g.degree()
    if m < n:
        return Rx.constant(0)
    elif m == n:
        return Rx.constant(f.lc() / g.lc())

    # h = g.rev_k(n).reciprocal_k(m - n + 1)
    # h.in_place_reciprocal_k(m - n + 1)
    h = Reciprocal(g.rev_k(n), Rx, m - n + 1)

    # qq = f.rev_k(m) * h
    # :
    # qq = FA.multiply_auto(f.rev_k(m), h)
    # qq.resize(m - n + 1)
    # q = qq.rev_k(m - n)
    q = FA.multiply_auto(f.rev_k(m), h)
    q.resize(m - n + 1)
    q.in_place_rev_k(m - n)
    assert q.degree() == m - n
    return q


def Reciprocal(f, Rx, k=None):
    """1/f modulo x^k"""
    if not f or f.degree() < 0 or not f[0]:
        raise ValueError("Reciprocal of zero polynomial or multiple of x.")
    if k is None:
        k = f.degree() + 1
    assert k > 0

    const = f[0]
    if k == 1:
        return Rx.constant(const.inverse())

    half_k = (k + 1) >> 1
    q = Reciprocal(f.resized(half_k), Rx=Rx, k=half_k)

    r = FA.multiply_auto(q.square(), f)
    r.resize(k)
    return r
