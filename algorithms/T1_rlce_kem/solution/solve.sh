#!/bin/bash
# Reference solution for T1_rlce_kem (RLCE-KEM 128A, parameter set ID 1).
#
# Implements the Couvreur-Lequesne-Tillich polynomial-time key-recovery attack
# (arXiv:1805.11489): a square-code distinguisher on shortened codes recovers the
# w hidden random-column twin pairs, the 2x2 mixing functionals, and the
# underlying GRS structure of the public code. That yields a decoder for the
# public RLCE code, which decodes the challenge ciphertext, recovers the message
# and error, and reconstructs the KEM shared secret via RLCEpadDecode.
#
# The attack applies because ID1 has w=96 < n-k=156 ("odd ID" parameters); it
# breaks the KEMSharedSecretRecoveryGame using only the public key + ciphertext.
#
# SageMath is available in the client image (conda-forge sage on PATH).
set -e

cat <<'RLCE_COMMON_EOF' > /app/rlce_common.py
"""RLCE-KEM 128A common primitives, pure-Python (no Sage needed).

Replicates: GF(2^10) packing, SHA-512 MGF1, and RLCEpadDecode, so that given the
recovered message symbols m (k FE) + error values/locations we can reconstruct the
shared secret exactly as crypto_kem_dec would.
"""
import hashlib

# Parameter set ID 1 (RLCE_KEM_128A)
N = 532
K = 376
W = 96
T = 78
M = 10           # GF(2^10)
NPW = N + W      # 628
K1 = 504         # para[6]
K2 = 32          # para[7]
K3 = 32          # para[8]
MLEN_BITS = 4540 # para[5]
PADDED_LEN = K1 + K2 + K3  # 568
CRYPTO_BYTES = 64

# ---------------- byte <-> field element (10-bit MSB-first packing) ----------
def b2fe10(data):
    """bytes -> list of 10-bit field elements (MSB-first bit packing)."""
    bits = 0
    nbits = 0
    out = []
    for byte in data:
        bits = (bits << 8) | byte
        nbits += 8
        while nbits >= 10:
            nbits -= 10
            out.append((bits >> nbits) & 0x3FF)
    return out

def fe2b10(fe, blen):
    """list of 10-bit field elements -> bytes (MSB-first), length blen."""
    bits = 0
    nbits = 0
    out = bytearray()
    for v in fe:
        bits = (bits << 10) | (v & 0x3FF)
        nbits += 10
        while nbits >= 8:
            nbits -= 8
            out.append((bits >> nbits) & 0xFF)
    if nbits > 0:
        out.append((bits << (8 - nbits)) & 0xFF)
    if len(out) < blen:
        out.extend(b'\x00' * (blen - len(out)))
    return bytes(out[:blen])

# ---------------- SHA-512 MGF1 (RLCE_MGF512) --------------------------------
def mgf512(seed, mask_len):
    out = bytearray()
    counter = 0
    while len(out) < mask_len:
        out += hashlib.sha512(seed + counter.to_bytes(4, 'big')).digest()
        counter += 1
    return bytes(out[:mask_len])

# ---------------- RLCEpadDecode ---------------------------------------------
def rlce_pad_decode(padded, err_locations):
    """padded: 568 bytes (m||errValue repacked). err_locations: sorted list of t
    error positions. Returns the k1-byte message (ss = first 64 bytes)."""
    assert len(padded) == PADDED_LEN
    e0 = bytearray()
    for loc in err_locations:
        e0.append((loc >> 8) & 0xFF)
        e0.append(loc & 0xFF)
    encoded = bytearray(padded)
    mh1Ph2 = bytes(encoded[:K1 + K2])
    h3 = mgf512(mh1Ph2, K3)
    randomness = bytearray(K3)
    for i in range(K3):
        randomness[i] = encoded[K1 + K2 + i] ^ h3[i]
    alpha = 8 * PADDED_LEN - MLEN_BITS  # = 4
    mask = (0xFF << alpha) & 0xFF
    randomness[K3 - 1] &= mask
    re0 = bytes(randomness) + bytes(e0)
    h2 = mgf512(re0, K1 + K2)
    for i in range(K1 + K2):
        encoded[i] ^= h2[i]
    message = bytes(encoded[:K1])
    # integrity check (RLCEpadDecode step 13): recomputed k2 hash must match
    mre0 = message + re0
    h1 = mgf512(mre0, K2)
    ok = (h1 == bytes(encoded[K1:K1 + K2]))
    return message, ok

def padded_and_locs_to_ss(padded, err_locations):
    msg, ok = rlce_pad_decode(padded, err_locations)
    return msg[:CRYPTO_BYTES], ok

def fevec_to_padded(m_syms, err_values):
    """m_syms: k field elements, err_values: t field elements -> 568-byte padded."""
    fe = list(m_syms) + list(err_values)
    assert len(fe) == K + T
    return fe2b10(fe, PADDED_LEN)
RLCE_COMMON_EOF

cat <<'RLCE_SAGE_EOF' > /app/rlce_sage.py
"""Shared Sage-side helpers: field, pk/sk parsing, SS recovery, folded GRS decode.
Imported by both the dev/validation scripts and (a trimmed copy) the final attack.
Run under `sage -python` or inside a .sage file (K defined via sage global).
"""
from sage.all import GF, Matrix, vector, codes, diagonal_matrix, PolynomialRing
from sage.coding.linear_code import LinearCode
import random as _random

# GF(2^10), primitive poly x^10 + x^3 + 1 (RLCE convention), generator = a (int 2)
K = GF(2**10, 'a', modulus=GF(2)['x']([1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]))

N, KK, W, T, M = 532, 376, 96, 78, 10
NPW = N + W            # 628
NMW = N - W            # 436 pure-GRS internal positions
REDUND = NPW - KK      # 252

def i2f(v):
    return K.from_integer(int(v))

def f2i(e):
    return int(e.to_integer())

# ---------------- 10-bit MSB-first packing ----------------
def b2fe10(data, count):
    bits = 0; nbits = 0; out = []
    for byte in data:
        bits = (bits << 8) | byte; nbits += 8
        while nbits >= 10 and len(out) < count:
            nbits -= 10; out.append((bits >> nbits) & 0x3FF)
    return out[:count]

# ---------------- public key ----------------
def parse_pk(pk_bytes):
    """pk_bytes: full public key (with 1 header byte). Returns Ghat = [I_k | Gpub]
    as a k x (n+w) matrix over K, plus Gpub field-element rows."""
    fe = b2fe10(pk_bytes[1:], KK * REDUND)
    Gpub = [[i2f(fe[r * REDUND + c]) for c in range(REDUND)] for r in range(KK)]
    rows = []
    for r in range(KK):
        row = [K(0)] * NPW
        row[r] = K(1)
        for c in range(REDUND):
            row[KK + c] = Gpub[r][c]
        rows.append(row)
    return Matrix(K, rows)

def parse_ct(ct_bytes):
    """785-byte ciphertext -> list of 628 field elements (cipherFE)."""
    fe = b2fe10(ct_bytes, NPW)
    return [i2f(v) for v in fe]

# ---------------- private key (GROUND TRUTH, dev only) ----------------
def parse_sk_truth(sk_bytes):
    """Returns dict with perm2 (internal->public), foldcoef list (96 pairs)."""
    off = 1
    perm1 = []
    for i in range(N):
        perm1.append((sk_bytes[off] << 8) | sk_bytes[off + 1]); off += 2
    perm2 = []
    for i in range(NPW):
        perm2.append((sk_bytes[off] << 8) | sk_bytes[off + 1]); off += 2
    # FE section
    u = 123
    invSLen = KK * (u + 1)
    totalFELen = 2 * W + invSLen + N + KK * REDUND
    fe = b2fe10(sk_bytes[off:], totalFELen)
    foldcoef = []
    for i in range(W):
        foldcoef.append((i2f(fe[2 * i]), i2f(fe[2 * i + 1])))
    return {"perm2": perm2, "foldcoef": foldcoef}

# ---------------- SS recovery ----------------
def ss_recover(G, tries=60):
    last = None
    for attempt in range(tries):
        try:
            return _ss_once(G, _random.Random(1000 + attempt))
        except ZeroDivisionError as e:
            last = e
    raise last

def _ss_once(G, rng):
    k = G.nrows(); Ncol = G.ncols()
    R = G.rref()
    info = list(R.pivots())
    red = [j for j in range(Ncol) if j not in set(info)]
    reds = list(red); rng.shuffle(reds)
    p, pp = reds[0], reds[1]
    def ratio(q):
        base = R[0, q]; return [R[i, q] / base for i in range(k)]
    rp = ratio(p); rpp = ratio(pp)
    Q = [rp[i] / rpp[i] for i in range(k)]
    vals = list(range(1, 1024)); rng.shuffle(vals)
    A = i2f(vals[0]); B = i2f(vals[1]); C = i2f(vals[2])
    xs = [None] * Ncol
    xs[info[0]] = A; xs[p] = B; xs[pp] = C
    for i in range(1, k):
        Qi = Q[i]
        num = Qi * (C - A) * B - (B - A) * C
        den = Qi * (C - A) - (B - A)
        xs[info[i]] = num / den
    x0 = xs[info[0]]; xp = xs[p]; xi = xs[info[1]]
    Rp1 = R[1, p] / R[0, p]
    for q in red:
        if q in (p, pp):
            continue
        Qp = (R[1, q] / R[0, q]) / Rp1
        coef = Qp * (xp - x0) - (xp - xi)
        rhs = Qp * xi * (xp - x0) - x0 * (xp - xi)
        xs[q] = rhs / coef
    # multipliers
    w = []
    for j in range(Ncol):
        prod = K(1); xj = xs[j]
        for l in range(Ncol):
            if l != j:
                prod *= (xj - xs[l])
        w.append(prod ** (-1))
    r = Ncol - k
    rows_eq = []
    for grow in G.rows():
        for s in range(r):
            rows_eq.append([w[j] * (xs[j] ** s) * grow[j] for j in range(Ncol)])
    Msys = Matrix(K, rows_eq)
    ns = Msys.right_kernel().basis()
    d = ns[0]
    ys = [d[j] ** (-1) for j in range(Ncol)]
    return xs, ys

# ---------------- folded GRS decode + solve m ----------------
def grs_decode(xs, ys, k, received):
    C = codes.GeneralizedReedSolomonCode(xs, k, ys)
    D = C.decoder("Gao")
    cw = D.decode_to_code(vector(K, received))
    return cw

def solve_message(Ghat, cipherFE, reliable_public):
    Msub = Ghat.matrix_from_columns(reliable_public)
    c_rel = vector(K, [cipherFE[p] for p in reliable_public])
    m = Msub.solve_left(c_rel)
    return m

# ---------------- P1: pairing via square-code shortening ----------------
def _shorten_gen(Ghat, L):
    Lset = set(L)
    cols = Ghat.matrix_from_columns(sorted(Lset))
    ker = cols.left_kernel().basis_matrix()
    kept = [j for j in range(NPW) if j not in Lset]
    SL = (ker * Ghat).matrix_from_columns(kept)
    return SL, kept

def _zero_positions(SL, kept):
    rows = SL.rows(); d = len(rows); ln = SL.ncols()
    prods = []
    for i in range(d):
        for j in range(i, d):
            prods.append([rows[i][t] * rows[j][t] for t in range(ln)])
    Sqr = Matrix(K, prods).row_space().basis_matrix()
    H = LinearCode(Sqr).parity_check_matrix()
    return set(kept[t] for t in range(ln) if H.column(t).is_zero())

def _shorten_further(SL, kept, i):
    li = kept.index(i)
    ker = SL.matrix_from_columns([li]).left_kernel().basis_matrix()
    newkept = [c for c in kept if c != i]
    keepcols = [t for t in range(len(kept)) if t != li]
    return (ker * SL).matrix_from_columns(keepcols), newkept

def recover_pairs(Ghat, ell=335, seed=7, max_rounds=40, log=lambda *a: None):
    rng = _random.Random(int(seed))
    found = set(); paired = set(); TW = set(); rnd = 0
    while len(found) < W and rnd < max_rounds:
        if not TW:
            L = rng.sample(range(NPW), ell)
        else:
            comp = [p for p in range(NPW) if p not in TW]
            L = list(TW) + rng.sample(comp, ell - len(TW))
        SL, kept = _shorten_gen(Ghat, L)
        TL = _zero_positions(SL, kept); TW |= TL
        remaining = set(TL) - paired
        while remaining:
            i = min(remaining)
            SL2, kept2 = _shorten_further(SL, kept, i)
            TL2 = _zero_positions(SL2, kept2)
            tw = (TL - {i}) - TL2
            if len(tw) == 1:
                j = next(iter(tw))
                found.add((i, j)); paired.add(i); paired.add(j)
                remaining.discard(i); remaining.discard(j)
            else:
                remaining.discard(i)
        rnd += 1
        log(f"  pairing round {rnd}: |TW|={len(TW)} pairs={len(found)}/{W}")
    pairs = [tuple(sorted(p)) for p in found]
    twin_positions = set(paired)
    pureGRS = sorted(p for p in range(NPW) if p not in twin_positions)
    return pairs, pureGRS

# ---------------- P2: foldcoef via support-point recovery ----------------
def recover_foldcoef(Ghat, pairs, pureGRS):
    Gp = Ghat.matrix_from_columns(pureGRS)     # k x |pureGRS|, a GRS code
    xs_p, ys_p = ss_recover(Gp)
    # pick k pure-GRS positions forming an info set (distinct support -> Vandermonde ok)
    idx = list(range(KK))
    chosen = [pureGRS[i] for i in idx]
    xch = [xs_p[i] for i in idx]; ych = [ys_p[i] for i in idx]
    V = Matrix(K, [[xch[i] ** j for j in range(KK)] for i in range(KK)])
    B = Ghat.matrix_from_columns(chosen).transpose()        # B*m = (c_chosen)
    D = diagonal_matrix(K, [y ** (-1) for y in ych])
    Mmap = V.inverse() * D * B                              # f_coeffs = Mmap * m
    MTinv = (Mmap.transpose()).inverse()
    foldcoef = []
    for (u, v) in pairs:
        a = MTinv * Ghat.column(u)
        b = MTinv * Ghat.column(v)
        lam, mu = _solve_pair(a, b)
        foldcoef.append((lam, mu))
    return foldcoef

def _eval_vec(xp):
    """evaluation covector v s.t. v.f_coeffs = f(xp). xp==None means point at infinity
    (leading-coefficient functional)."""
    if xp is None:
        v = [K(0)] * KK; v[KK - 1] = K(1)
        return vector(K, v)
    return vector(K, [xp ** j for j in range(KK)])

def _solve_pair(a, b):
    """find (lam,mu) with  v(x) == lam*a + mu*b  for some support point x in P^1(GF q).
    x ranges over GF(q) and the point at infinity (leading-coeff functional)."""
    Mab = Matrix(K, [list(a), list(b)]).transpose()   # k x 2, columns a,b
    def try_v(vx):
        try:
            z = Mab.solve_right(vx)
        except ValueError:
            return None
        return (z[0], z[1]) if (Mab * z == vx) else None
    # quadratic candidates (finite x) from coords 0,1,2
    a0, a1, a2 = a[0], a[1], a[2]
    b0, b1, b2 = b[0], b[1], b[2]
    D = a0 * b1 - a1 * b0
    cand = []
    if D != 0:
        PR = PolynomialRing(K, 'X'); X = PR.gen()
        poly = D * X**2 + (a2 * b0 - a0 * b2) * X + (a1 * b2 - a2 * b1)
        cand = [r for r, _ in poly.roots()]
    for xp in cand:
        r = try_v(_eval_vec(xp))
        if r is not None:
            return r
    # point at infinity
    r = try_v(_eval_vec(None))
    if r is not None:
        return r
    # fallback: full scan over the field (including 0)
    for vi in range(0, 1024):
        r = try_v(_eval_vec(i2f(vi)))
        if r is not None:
            return r
    raise RuntimeError("foldcoef recovery failed for a pair")

# ---------------- full decode: fold + SS + GRS-decode + solve m ----------------
def decode_message(Ghat, cipherFE, pairs, pureGRS, foldcoef):
    cols = [Ghat.column(p) for p in pureGRS]
    for (u, v), (lam, mu) in zip(pairs, foldcoef):
        cols.append(lam * Ghat.column(u) + mu * Ghat.column(v))
    Gf = Matrix(K, cols).transpose()          # k x n
    xs, ys = ss_recover(Gf)
    cf = [cipherFE[p] for p in pureGRS]
    for (u, v), (lam, mu) in zip(pairs, foldcoef):
        cf.append(lam * cipherFE[u] + mu * cipherFE[v])
    cw = grs_decode(xs, ys, KK, cf)   # error-free folded codeword = m * Gf
    # recover m directly from the corrected folded codeword (robust to how the
    # 78 errors distribute across pure-GRS / pair positions, incl. cancellation)
    m = Gf.solve_left(vector(K, list(cw)))
    c0 = m * Ghat
    return m, c0
RLCE_SAGE_EOF

cat <<'ATTACK_SAGE_EOF' > /app/attack.sage
#!/usr/bin/env sage
# Couvreur-Lequesne-Tillich square-code key-recovery attack on RLCE-KEM (ID1).
# Recovers the shared secret of a KEMSharedSecretRecoveryGame challenge from the
# public key + encapsulation alone (no private key), then submits it.
import sys, os, json, subprocess
sys.path.insert(0, "/app")
import rlce_sage as R
import rlce_common as C
from rlce_sage import f2i

SERVER_URL = os.environ.get("GC_URL", "http://game_controller:8000")

def curl_post(url, data):
    r = subprocess.run(
        ["curl", "-s", "-X", "POST", url,
         "-H", "Content-Type: application/json", "-d", json.dumps(data)],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("curl failed: " + r.stderr)
    return json.loads(r.stdout)

def unhex(s):
    return bytes.fromhex(s[2:] if s[:2] in ("0x", "0X") else s)

# ---- Stage 0: obtain public key + encapsulation ----
resp = curl_post(SERVER_URL + "/execute_current_stage", {"stage_payload": {}})
sr = resp["stage_result"]
pk = unhex(sr["public_key"])
ct = unhex(sr["encapsulation"])
print("got pk %d bytes, ct %d bytes" % (len(pk), len(ct)))

Ghat = R.parse_pk(pk)
cipherFE = R.parse_ct(ct)

# ---- run the attack (retry with fresh randomness on failure) ----
ss = None
for attempt in range(6):
    try:
        pairs, pureGRS = R.recover_pairs(Ghat, seed=7 + 101 * attempt, log=print)
        if len(pairs) != R.W:
            print("attempt %d: only %d/96 pairs" % (attempt, len(pairs))); continue
        foldcoef = R.recover_foldcoef(Ghat, pairs, pureGRS)
        m, c0 = R.decode_message(Ghat, cipherFE, pairs, pureGRS, foldcoef)
        wt = sum(1 for i in range(R.NPW) if c0[i] != cipherFE[i])
        print("attempt %d: codeword distance %d" % (attempt, wt))
        if wt > R.T:
            continue
        m_syms = [f2i(m[i]) for i in range(R.KK)]
        err_pos = sorted(i for i in range(R.NPW) if c0[i] != cipherFE[i])
        err_vals = [f2i(cipherFE[i] - c0[i]) for i in err_pos]
        padded = C.fevec_to_padded(m_syms, err_vals)
        cand, ok = C.padded_and_locs_to_ss(padded, err_pos)
        if not ok:
            print("attempt %d: padding integrity check failed" % attempt); continue
        ss = cand
        print("attempt %d: SUCCESS, ss recovered" % attempt)
        break
    except Exception as e:
        print("attempt %d failed: %s: %s" % (attempt, type(e).__name__, e))
        continue

if ss is None:
    print("ERROR: attack failed to recover shared secret")
    sys.exit(1)

# ---- Stage 1: submit the recovered shared secret ----
recovered = "0x" + ss.hex()
resp = curl_post(SERVER_URL + "/execute_current_stage",
                 {"stage_payload": {"recovered_shared_secret": recovered}})
print("submit response:", resp)
if resp.get("stage_result", {}).get("Game won") == "Yes":
    print("GAME WON")
else:
    print("GAME LOST")
ATTACK_SAGE_EOF

cat <<'ATTACK_SH_EOF' > /app/attack.sh
#!/bin/bash
sage /app/attack.sage
ATTACK_SH_EOF
chmod +x /app/attack.sh

echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt
echo "solve.sh: wrote /app/attack.sh, /app/attack.sage, helper modules, and security_game_choice.txt"
