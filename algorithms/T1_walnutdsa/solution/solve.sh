#!/bin/bash
# WalnutDSA universal-forgery solution for SignatureForgeryGame.
# Attack: Beullens-Blackburn (ASIACRYPT 2018, eprint 2018/318) Section 5 -- Reversing
# E-Multiplication via the subgroup-chain meet-in-the-middle. Recover equivalent braids
# (s1',s2') from the public key (+ one sign-oracle call for sigma(s2)) by descending the
# chain A^{(7)}>...>A^{(0)} one level per birthday MITM over right cosets, with the S5.4
# transport trick and parallel (8-CPU) id-table build + probe; rare subgroup-chain
# assumption failures are escaped by retrying with a different transport (bounded by
# FORGE_BUDGET_SEC). Then forge sig = s1'^{-1}.E(d).s2'. Verified end-to-end against the
# reference cli (valid=true). Pure Python / stdlib.
set -e
mkdir -p /app

cat > /app/walnut.py <<'WALNUT_PY'
"""WalnutDSA (walnut128, N=8, q=2^5) core: GF(2^5), braid packing, E-multiplication,
public-key parsing, message encoding. Mirrors the vendored reference C exactly."""

# ---- GF(2^5) with reducing polynomial x^5 + x^2 + 1 (0x25 = 37) ----
def _build_gf():
    POLY = 0x25  # x^5 + x^2 + 1
    def gmul(a, b):
        r = 0
        for _ in range(5):
            if b & 1:
                r ^= a
            b >>= 1
            hi = a & 0x10
            a = (a << 1) & 0x1F
            if hi:
                a ^= (POLY & 0x1F)  # subtract x^5 term -> x^2+1 = 5
        return r
    GMUL = [[gmul(a, b) for b in range(32)] for a in range(32)]
    MINV = [0]*32
    for a in range(1, 32):
        for b in range(1, 32):
            if GMUL[a][b] == 1:
                MINV[a] = b
                break
    return GMUL, MINV

GMUL, MINV = _build_gf()
N = 8

def gmul(a, b):
    if a >= 32 or b >= 32:
        return 0
    return GMUL[a][b]

def minv(a):
    if a >= 32:
        return 0
    return MINV[a]

# ---- braid packing ----
# braid bytes: [len_hi, len_lo, then nibbles packed 2-per-byte, high nibble first]
# generator nibble: bit3 = sign(inverse), bits0-2 = strand (1-indexed in C macro)
def braid_num_generators(braid):
    return (braid[0] << 8) | braid[1]

def braid_get_generator(braid, pos):
    # mirrors GET_BRAID_GENERATOR(braid,pos): braid[0],[1] are the length header
    byte = braid[(pos // 2) + 2]
    if pos % 2:
        return byte & 0x0F
    return (byte >> 4) & 0x0F

def pack_braid(gens):
    """gens: list of (strand, sign) with strand in 1..7, sign 0 or 1 -> packed nibbles."""
    n = len(gens)
    out = [(n >> 8) & 0xFF, n & 0xFF]
    nibbles = [((1 if s else 0) << 3) | (strand & 0x07) for (strand, s) in gens]
    if len(nibbles) % 2:
        nibbles.append(0)
    for i in range(0, len(nibbles), 2):
        out.append((nibbles[i] << 4) | nibbles[i+1])
    return bytes(out)

# ---- E-multiplication: (M, perm) * braid, with T-values ----
def emul(M, perm, braid, T):
    """M: 8x8 list of lists (GF elems), perm: list of 8 (0-indexed), braid: bytes, T: list of 8.
    Modifies and returns (M, perm). Mirrors walnut_emul exactly."""
    M = [row[:] for row in M]
    perm = perm[:]
    ng = braid_num_generators(braid)
    for c in range(ng):
        g = braid_get_generator(braid, c)
        i = g & 0x07           # strand (0-indexed here since C uses i directly as index)
        if i >= N - 1:
            raise ValueError("bad strand")
        e = g & 0x08
        if e == 0:
            a = T[perm[i]]; b = a; cc = 1
        else:
            a = 1; b = minv(T[perm[i+1]]); cc = b
        if i != 0:
            for j in range(N):
                M[j][i-1] ^= gmul(M[j][i], a)
        for j in range(N):
            M[j][i+1] ^= gmul(M[j][i], cc)
        for j in range(N):
            M[j][i] = gmul(M[j][i], b)
        perm[i], perm[i+1] = perm[i+1], perm[i]
    return M, perm

def mmul(A, B):
    D = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            s = 0
            for k in range(N):
                s ^= gmul(A[i][k], B[k][j])
            D[i][j] = s
    return D

def identity():
    return [[1 if i == j else 0 for j in range(N)] for i in range(N)]

# ---- bit extraction (extract_elem) ----
def extract_elem(buf, curr_bit, packwidth):
    val = 0
    for k in range(packwidth):
        bitpos = curr_bit + k
        byte = buf[bitpos // 8]
        bit = (byte >> (7 - (bitpos % 8))) & 1
        val = (val << 1) | bit
    return val

# ---- public key parse ----
# layout: version(3) | Tvalues(8*5 bits=5 bytes) | S_matrix | S_perm | S'_matrix
VERSION_LEN = 3
TVAL_BITS = 5
NUM_TVALUES = 8
TVALUES_POS = VERSION_LEN
TVALUES_LEN = (NUM_TVALUES * TVAL_BITS) // 8  # 5
MATRIX_ELEM_BITS = 5
NUM_MATRIX_ELEMENTS = 64
# WALNUT_PUBKEY_MATRIX_LENGTH = ((64 - 8 + 1)*5 + 7)//8
MATRIX_LEN = ((NUM_MATRIX_ELEMENTS - N + 1) * MATRIX_ELEM_BITS + 7) // 8
PERM_ELEM_BITS = 3  # B8_STRAND_BITS
PERM_LEN = (N * PERM_ELEM_BITS) // 8  # 3
S_MATRIX_POS = TVALUES_POS + TVALUES_LEN
S_PERM_POS = S_MATRIX_POS + MATRIX_LEN
SPRIME_MATRIX_POS = S_PERM_POS + PERM_LEN

def parse_pubkey(pk):
    T = [extract_elem(pk[TVALUES_POS:], i*TVAL_BITS, TVAL_BITS) for i in range(NUM_TVALUES)]
    def parse_matrix(base):
        M = [[0]*N for _ in range(N)]
        for i in range(N):
            if i != N-1:
                for j in range(N):
                    M[i][j] = extract_elem(pk[base:], MATRIX_ELEM_BITS*(j + i*N), MATRIX_ELEM_BITS)
        M[N-1][N-1] = extract_elem(pk[base:], MATRIX_ELEM_BITS*((N-1)*N), MATRIX_ELEM_BITS)
        return M
    M2 = parse_matrix(S_MATRIX_POS)        # P(s1) matrix
    perm2 = [extract_elem(pk[S_PERM_POS:], i*PERM_ELEM_BITS, PERM_ELEM_BITS) for i in range(N)]
    Mprime = parse_matrix(SPRIME_MATRIX_POS)  # M2 = mat(P(s2))
    return T, M2, perm2, Mprime

# ---- message encoding: SHA-256 hash -> braid ----
import hashlib

# pure braid generators g_i^e as lists of (strand, sign), strand 1-indexed.
# Derived from pure_braid_generators packed nibbles in walnut_message_encoder.
def _unpack_gen_row(packed_nibbles, ngen):
    gens = []
    for pos in range(ngen):
        byte = packed_nibbles[pos // 2]
        nib = (byte >> 4) if (pos % 2 == 0) else (byte & 0x0F)
        gens.append((nib & 0x07, 1 if (nib & 0x08) else 0))
    return gens

_PB = [
    (14, [0x65,0x43,0x21,0x00,0x9A,0xBC,0xDE]),
    (10, [0x65,0x43,0x22,0xBC,0xDE]),
    (6,  [0x65,0x44,0xDE]),
    (2,  [0x66]),
    (16, [0x65,0x43,0x21,0x00,0x00,0x9A,0xBC,0xDE]),
    (12, [0x65,0x43,0x22,0x22,0xBC,0xDE]),
    (8,  [0x65,0x44,0x44,0xDE]),
    (4,  [0x66,0x66]),
    (18, [0x65,0x43,0x21,0x00,0x00,0x00,0x9A,0xBC,0xDE]),
    (14, [0x65,0x43,0x22,0x22,0x22,0xBC,0xDE]),
    (10, [0x65,0x44,0x44,0x44,0xDE]),
    (6,  [0x66,0x66,0x66]),
    (20, [0x65,0x43,0x21,0x00,0x00,0x00,0x00,0x9A,0xBC,0xDE]),
    (16, [0x65,0x43,0x22,0x22,0x22,0x22,0xBC,0xDE]),
    (12, [0x65,0x44,0x44,0x44,0x44,0xDE]),
    (8,  [0x66,0x66,0x66,0x66]),
]
PURE_GENS = [_unpack_gen_row(p, ng) for (ng, p) in _PB]

def encode_message_gens(message_bytes):
    """Return the list of (strand,sign) generators for E(message) WITHOUT free reduction."""
    h = hashlib.sha256(message_bytes).digest()
    gens = []
    # 64 nibbles, high nibble of byte first (GET_BRAID_GENERATOR semantics)
    for i in range(64):
        byte = h[i // 2]
        block = (byte >> 4) if (i % 2 == 0) else (byte & 0x0F)
        gens.extend(PURE_GENS[block])
    return gens

def free_reduce(gens):
    """Free reduction: cancel adjacent b_i b_i^{-1}."""
    stack = []
    for (s, sign) in gens:
        if stack:
            ps, psign = stack[-1]
            if ps == s and psign != sign:
                stack.pop()
                continue
        stack.append((s, sign))
    return stack

def encode_message_braid(message_bytes):
    return pack_braid(free_reduce(encode_message_gens(message_bytes)))

WALNUT_PY

cat > /app/solver.py <<'SOLVER_PY'
"""Full WalnutDSA REM solver: subgroup-chain MITM (Beullens-Blackburn S5.2-5.4)."""
import walnut as w
import random, time, sys
import multiprocessing as mp
import gc
N = 8
NPROC = 8

def realize_perm(target):
    """Band-gen braid whose E-mult permutation (applied to identity) equals target."""
    cur = list(range(N))
    gens = []
    for p in range(N):
        q = cur.index(target[p], p)
        while q > p:
            cur[q], cur[q - 1] = cur[q - 1], cur[q]
            gens.append((q - 1, 0))
            q -= 1
    return gens

# globals shared with forked probe workers
_PW = {}

def _probe_worker(args):
    wi_lo, wi_hi = args
    M_cur = _PW['M']; m = _PW['m']; T = _PW['T']; base_seed = _PW['bs']
    walk_len = _PW['wl']; packed = _PW['packed']; id_table = _PW['idt']
    np_ = len(packed)
    we = w.emul
    for wi in range(wi_lo, wi_hi):
        rM = random.Random(f'{base_seed}|M|{wi}')
        XM = [row[:] for row in M_cur]; pM = list(range(N))
        for q in range(1, walk_len + 1):
            c = rM.randrange(np_)
            XM, pM = we(XM, pM, packed[c], T)
            k = coset_key(XM, m)
            hit = id_table.get(k)
            if hit is not None:
                return (wi, q, hit)
    return None

def emul(M, perm, gens, T):
    return w.emul(M, perm, w.pack_braid(gens), T)

def invert_gens(gens):
    return [(s, 1 - sg) for (s, sg) in reversed(gens)]

def Aij(i, j):
    """Pure-braid generator A_{i,j}, 0<=i<j, band gens; permutation = identity."""
    pre = [(t, 0) for t in range(j - 1, i, -1)]
    mid = [(i, 0), (i, 0)]
    post = [(t, 1) for t in range(i + 1, j)]
    return pre + mid + post

# --- single band-generator E-mult applied in place to a maintained matrix (perm fixed via T-perm) ---
def apply_gen_matrix(M, gen_strand, gen_sign, perm, T):
    """Apply one band generator (strand i, sign) to (M, perm); returns new (M, perm). Column ops."""
    return w.emul(M, perm, w.pack_braid([(gen_strand, gen_sign)]), T)

_GMUL = w.GMUL
_MINV = w.MINV

def coset_key(X, m):
    """Coset of A^{(m-1)} for X in A^{(m)}: (row m-1 [cols 0..m], rowspace(rows 0..m-1) via RREF over cols 0..m).
    For X in A^{(m)}, cols m+1..N-1 of rows 0..m-1 are identically 0, so restricting the RREF to cols 0..m
    yields the same (complete) rowspace invariant. Returned PACKED AS BYTES (each GF(32) value < 256):
    a single bytes object is much cheaper to hash, pickle (parallel IPC) and store than nested tuples."""
    ncol = m + 1
    nr = m
    M = [X[i][:ncol] for i in range(nr)]
    r = 0
    for c in range(ncol):
        piv = -1
        for rr in range(r, nr):
            if M[rr][c] != 0:
                piv = rr; break
        if piv < 0:
            continue
        if piv != r:
            M[r], M[piv] = M[piv], M[r]
        Mr = M[r]
        gi = _GMUL[_MINV[Mr[c]]]
        M[r] = Mr = [gi[x] for x in Mr]
        for rr in range(nr):
            if rr != r:
                Mrr = M[rr]
                f = Mrr[c]
                if f != 0:
                    gf = _GMUL[f]
                    M[rr] = [Mrr[k] ^ gf[Mr[k]] for k in range(ncol)]
        r += 1
        if r == nr:
            break
    out = bytearray(X[m - 1][:ncol])
    for row in M:
        out.extend(row)
    return bytes(out)

def in_Am(X, m):
    for i in range(m, N):
        for j in range(N):
            if X[i][j] != (1 if i == j else 0):
                return False
    for j in range(m + 1, N):
        for i in range(N):
            if X[i][j] != (1 if i == j else 0):
                return False
    return True

def genpool(m):
    """Pure-braid generators available to reduce into A^{(m-1)}: A_{i,j} with j<=m."""
    pool = []
    for j in range(1, m + 1):
        for i in range(0, j):
            pool.append(Aij(i, j))
    return pool

def _walk_braid(pool, base_seed, wi, p):
    """Reconstruct the braid (band gens) for the first p steps of walk wi."""
    r = random.Random(f'{base_seed}|id|{wi}')
    np_ = len(pool)
    g = []
    for _ in range(p):
        g += pool[r.randrange(np_)]
    return g

def mitm_level(M_cur, m, T, base_seed, walk_len=200, max_walks=4_000_000, log=sys.stderr):
    """Find a SHORT pure braid s_step with M_cur . P(s_step) in A^{(m-1)} via many-short-walk MITM."""
    pool = genpool(m)
    np_ = len(pool)
    id_table = {}
    id_table[coset_key(w.identity(), m)] = (-1, 0)  # identity coset reachable with empty braid
    # interleave id-side and M-side short walks until a cross-collision appears
    wi = 0
    while wi < max_walks:
        # identity-side walk
        r = random.Random(f'{base_seed}|id|{wi}')
        X = w.identity(); perm = list(range(N))
        for p in range(1, walk_len + 1):
            c = r.randrange(np_)
            X, perm = emul(X, perm, pool[c], T)
            k = coset_key(X, m)
            if k not in id_table:
                id_table[k] = (wi, p)
        # M-side walk (different seed namespace)
        rM = random.Random(f'{base_seed}|M|{wi}')
        XM = [row[:] for row in M_cur]; pM = list(range(N))
        Mchoices = []
        for q in range(1, walk_len + 1):
            c = rM.randrange(np_)
            XM, pM = emul(XM, pM, pool[c], T)
            Mchoices.append(c)
            k = coset_key(XM, m)
            hit = id_table.get(k)
            if hit is not None:
                iwi, ip = hit
                idg = _walk_braid(pool, base_seed, iwi, ip) if iwi >= 0 else []
                Mg = []
                for cc in Mchoices:
                    Mg += pool[cc]
                return Mg + invert_gens(idg)
        if wi % 1000 == 0:
            print(f"    [mitm m? walks={wi} table={len(id_table)}]", flush=True, file=log)
        wi += 1
    return None

def _build_worker(args):
    wi_lo, wi_hi = args
    m = _PW['m']; T = _PW['T']; base_seed = _PW['bs']; walk_len = _PW['wl']; packed = _PW['packed']
    np_ = len(packed)
    we = w.emul
    part = {}
    for wi in range(wi_lo, wi_hi):
        r = random.Random(f'{base_seed}|id|{wi}')
        X = w.identity(); perm = list(range(N))
        for p in range(1, walk_len + 1):
            c = r.randrange(np_)
            X, perm = we(X, perm, packed[c], T)
            k = coset_key(X, m)
            if k not in part:
                part[k] = (wi, p)
    return part

def _reconstruct_M_braid(base_seed, wi, q, pool):
    r = random.Random(f'{base_seed}|M|{wi}')
    np_ = len(pool)
    g = []
    for _ in range(q):
        g += pool[r.randrange(np_)]
    return g

def mitm_level_par(M_cur, m, T, base_seed, walk_len=200, id_walks=15000,
                   nproc=8, probe_batch=20000, max_probe_walks=4_000_000, log=sys.stderr):
    """Parallel asymmetric MITM: build a fixed id-table, then probe M-walks across nproc cores."""
    pool = genpool(m)
    packed = [w.pack_braid(g) for g in pool]
    np_ = len(pool)
    _PW.update({'M': M_cur, 'm': m, 'T': T, 'bs': base_seed, 'wl': walk_len,
                'pool': pool, 'packed': packed})
    # --- phase 1: build id-table (parallel across nproc) ---
    id_table = {coset_key(w.identity(), m): (-1, 0)}
    if id_walks >= 2000:
        chunk = (id_walks + nproc - 1) // nproc
        ranges = [(i * chunk, min((i + 1) * chunk, id_walks)) for i in range(nproc)]
        with mp.get_context('fork').Pool(nproc) as bpool:
            for part in bpool.imap_unordered(_build_worker, ranges):
                for k, v in part.items():
                    if k not in id_table:
                        id_table[k] = v
    else:
        we = w.emul
        for wi in range(id_walks):
            r = random.Random(f'{base_seed}|id|{wi}')
            X = w.identity(); perm = list(range(N))
            for p in range(1, walk_len + 1):
                c = r.randrange(np_)
                X, perm = we(X, perm, packed[c], T)
                k = coset_key(X, m)
                if k not in id_table:
                    id_table[k] = (wi, p)
    print(f"    [par m={m}] id-table built: {len(id_table)} cosets from {id_walks} walks", flush=True, file=log)
    # --- phase 2: parallel probe ---
    _PW['idt'] = id_table
    probed = 0
    result = None
    per = probe_batch // nproc
    ctx = mp.get_context('fork')
    while probed < max_probe_walks and result is None:
        ranges = [(probed + i * per, probed + (i + 1) * per) for i in range(nproc)]
        # Fresh short-lived pool per batch, fully drained then closed -- no mid-imap
        # terminate() (which can deadlock the pool inside the harbor container). Each
        # worker's range is small (~per walks) so a batch finishes quickly even when the
        # collision is in the first range.
        poolp = ctx.Pool(nproc)
        try:
            for res in poolp.map(_probe_worker, ranges):
                if res is not None and result is None:
                    result = res
        finally:
            poolp.close()
            poolp.join()
        probed += probe_batch
        if result is None:
            print(f"    [par m={m}] probed {probed} M-walks, no collision yet", flush=True, file=log)
    # free the (possibly large) id-table promptly before reconstructing / returning
    _PW.pop('idt', None)
    del id_table
    gc.collect()
    if result is not None:
        Mwi, Mq, (iwi, ip) = result
        idg = _walk_braid(pool, base_seed, iwi, ip) if iwi >= 0 else []
        Mg = _reconstruct_M_braid(base_seed, Mwi, Mq, pool)
        return Mg + invert_gens(idg)
    return None

def _transport_braid(attempt):
    """Build a transport braid whose permutation pt sends the two T=1 positions (0,1)
    to the back (pt[6],pt[7] in {0,1}), so the permuted T' has its last two values = 1.
    attempt 0 is the canonical transport; attempt>0 also (a) randomizes the middle
    ordering and (b) appends a random PURE braid (sigma=e, so T' keeps last-two=1) which
    left-multiplies M' by a random pure-braid matrix -- a much stronger perturbation of
    the reduced instance that escapes subgroup-chain assumption failures (S5.2) which the
    mere T'-reordering does not."""
    if attempt == 0:
        pt = [2, 3, 4, 5, 6, 7, 0, 1]
        return realize_perm(pt)
    rng = random.Random(f'transport|{attempt}')
    mid = [2, 3, 4, 5, 6, 7]
    rng.shuffle(mid)
    back = [0, 1]
    rng.shuffle(back)
    pt = mid + back
    tbr = realize_perm(pt)
    # random pure-braid suffix (does not change the permutation pt)
    suffix = []
    for _ in range(rng.randrange(10, 24)):
        j = rng.randrange(1, N)
        i = rng.randrange(0, j)
        suffix += Aij(i, j)
    return tbr + suffix

def solve_rem(M_target, perm_target, T, base_seed=0, walk_len=200, attempt=0, log=sys.stderr):
    """Find braid s with (1,e) *_T s = (M_target, perm_target). Uses transport trick."""
    # --- transport: move the two T-values (==1) to the back ---
    tbr = _transport_braid(attempt)
    Mt, pt = emul(w.identity(), list(range(N)), tbr, T)
    # T' = [T[pt[i]]]
    Tp = [T[pt[i]] for i in range(N)]
    # M' = Mt^{-1} . M_target
    Mt_inv = matinv(Mt)
    Mp = w.mmul(Mt_inv, M_target)
    # pi' = pt^{-1} o perm_target
    pt_inv = [0] * N
    for i in range(N):
        pt_inv[pt[i]] = i
    pip = [pt_inv[perm_target[i]] for i in range(N)]
    s2 = solve_rem_core(Mp, pip, Tp, base_seed, walk_len, log)
    if s2 is None:
        return None
    sol = tbr + s2
    return sol

def solve_rem_core(M_target, perm_target, T, base_seed, walk_len, log):
    # Step 1: reduce permutation to identity.
    M = [r[:] for r in M_target]; perm = perm_target[:]
    cur = perm[:]; pg = []
    for pos in range(N):
        idx = cur.index(pos)
        while idx > pos:
            cur[idx], cur[idx - 1] = cur[idx - 1], cur[idx]
            pg.append((idx - 1, 0)); idx -= 1
    M, perm = emul(M, perm, pg, T)
    if perm != list(range(N)):
        print("perm reduction failed", file=log); return None
    red = list(pg)
    # Step 2: column/row chain m = N-1 .. 1, reducing into A^{(m-1)}.
    for m in range(N - 1, 0, -1):
        if in_Am(M, m - 1):
            continue
        t0 = time.time()
        s_step = None
        # Level-aware escalation. Only the upper levels (m>=5, dominant coset ~q^9 with
        # last-two-T'=1) need the big 50000-tier table; the lower levels (m<=4) have tiny
        # cosets fully covered by id_walks<=6000, so if THEY fail it's the chain's
        # assumption failure (Beullens-Blackburn S5.2) -- fail fast (no wasteful 8 GB
        # build) and let the caller retry with a different transport.
        tiers = (300, 6000, 50000) if m == 5 else (300, 6000)
        for id_walks in tiers:
            # generous probe at the small tiers; tight ceiling at the 50000 tier so a
            # stuck dominant (assumption failure) is detected fast (~150k walks is far
            # above the ~37k expected for the true q^9 coset).
            mpw = id_walks * 3 if id_walks >= 50000 else id_walks * 16
            s_step = mitm_level_par(M, m, T, (base_seed, m), walk_len=walk_len,
                                    id_walks=id_walks, nproc=NPROC,
                                    probe_batch=NPROC * 5000,
                                    max_probe_walks=max(4800, mpw), log=log)
            if s_step is not None:
                break
            print(f"[REM] level m={m}: id_walks={id_walks} insufficient, escalating", file=log, flush=True)
        gc.collect()
        if s_step is None:
            print(f"[REM] level m={m} FAILED", file=log); return None
        M, perm = emul(M, perm, s_step, T)
        red += s_step
        if not in_Am(M, m - 1):
            print(f"[REM] level m={m} did not reduce!", file=log); return None
        print(f"[REM] level m={m} -> A^{{{m-1}}} ok  |s_step|={len(s_step)} t={time.time()-t0:.1f}s", file=log, flush=True)
    if M != w.identity():
        print("[REM] final matrix != I", file=log); return None
    return invert_gens(red)

def matinv(A):
    n = len(A)
    M = [A[i][:] + [1 if i == j else 0 for j in range(n)] for i in range(n)]
    r = 0
    for c in range(n):
        piv = -1
        for rr in range(r, n):
            if M[rr][c] != 0:
                piv = rr; break
        if piv < 0:
            return None
        M[r], M[piv] = M[piv], M[r]
        inv = w.minv(M[r][c]); M[r] = [w.gmul(x, inv) for x in M[r]]
        for rr in range(n):
            if rr != r and M[rr][c] != 0:
                f = M[rr][c]; M[rr] = [M[rr][k] ^ w.gmul(f, M[r][k]) for k in range(2 * n)]
        r += 1
    return [row[n:] for row in M]

SOLVER_PY

cat > /app/forge.py <<'FORGE_PY'
#!/usr/bin/env python3
"""WalnutDSA equivalent-key recovery (REM, Beullens-Blackburn S5.2-5.4) + universal forgery.
Args: <public_key_hex> <probe_signature_hex> <probe_message_hex>.
Prints 'message: 0x...' and 'signature: 0x...' for a fresh (never-queried) message."""
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walnut as w
import solver
N = 8


DEADLINE = None  # wall-clock cutoff (set in main)

def solve_rem_robust(M, perm, T, tag, attempts=6):
    for a in range(attempts):
        if DEADLINE is not None and time.time() > DEADLINE:
            print(f"[forge] REM {tag} budget exhausted at attempt {a}", file=sys.stderr, flush=True)
            return None
        # vary BOTH the walk seed and the transport (attempt) so a retry escapes
        # the rare subgroup-chain assumption failure, not just bad walk luck.
        sol = solver.solve_rem(M, perm, T, base_seed=f"{tag}-{a}", walk_len=200, attempt=a)
        if sol is not None:
            Ms, ps = w.emul(w.identity(), list(range(N)), w.pack_braid(sol), T)
            if Ms == M and ps == perm:
                return sol
        print(f"[forge] REM {tag} attempt {a} failed, retrying with new transport", file=sys.stderr, flush=True)
    return None


def main():
    global DEADLINE
    # Bound total wall time so a pathological (assumption-failure) keypair fails fast
    # (well under the verifier timeout) instead of stalling -- the verifier re-draws a
    # fresh keypair on the next run, and the typical keypair forges in a few minutes.
    DEADLINE = time.time() + float(os.environ.get("FORGE_BUDGET_SEC", "1500"))
    pk_hex, probe_sig_hex, probe_msg_hex = sys.argv[1], sys.argv[2], sys.argv[3]
    pk = bytes.fromhex(pk_hex[2:] if pk_hex.startswith("0x") else pk_hex)
    T, M1pub, perm1pub, Mprime = w.parse_pubkey(pk)

    # Derive perm(s2) from one oracle signature: sigma(s1) o sigma(sig) = sigma(s2).
    # This is REQUIRED: without it (Mprime, identity) is not a valid orbit element and
    # the s2 REM is unsolvable. Fail loudly rather than silently using the wrong perm.
    if not probe_sig_hex or probe_sig_hex in ("", "0x"):
        print("ERROR: empty probe signature -- cannot derive perm(s2)", file=sys.stderr)
        sys.exit(4)
    sigb = bytes.fromhex(probe_sig_hex[2:] if probe_sig_hex.startswith("0x") else probe_sig_hex)
    ng = w.braid_num_generators(sigb)
    nb = ((ng + 1) // 2) + 2
    _, sperm = w.emul(w.identity(), list(range(N)), sigb[:nb], T)
    perm_s2 = [perm1pub[sperm[i]] for i in range(N)]

    t0 = time.time()
    s1g = solve_rem_robust(M1pub, perm1pub, T, "s1")
    print(f"[forge] s1' recovered t={time.time()-t0:.1f}s", file=sys.stderr, flush=True)
    # For s2 only the matrix part is checked by verification; recover (Mprime, perm_s2).
    s2g = solve_rem_robust(Mprime, perm_s2, T, "s2")
    print(f"[forge] s2' recovered t={time.time()-t0:.1f}s", file=sys.stderr, flush=True)
    if s1g is None or s2g is None:
        print("REM_FAILED", file=sys.stderr)
        sys.exit(2)

    probe = bytes.fromhex(probe_msg_hex[2:] if probe_msg_hex.startswith("0x") else probe_msg_hex)
    while True:
        target = os.urandom(33)
        if target != probe:
            break

    ed = w.free_reduce(w.encode_message_gens(target))
    full = w.free_reduce(solver.invert_gens(s1g) + ed + s2g)
    sig_braid = w.pack_braid(full)
    blob = sig_braid + target

    # offline self-check against the exact verification equation
    LHS, _ = w.emul(M1pub, perm1pub, sig_braid, T)
    M1, _ = w.emul(w.identity(), list(range(N)), w.encode_message_braid(target), T)
    RHS = w.mmul(M1, Mprime)
    if LHS != RHS:
        print("SELFCHECK_FAILED", file=sys.stderr)
        sys.exit(3)

    print("message: 0x" + target.hex())
    print("signature: 0x" + blob.hex())


if __name__ == "__main__":
    main()

FORGE_PY

cat > /app/attack.sh <<'ATTACK_EOF'
#!/bin/bash
set -e
SERVER_URL="http://game_controller:8000"
resp=$(curl -s -X POST "$SERVER_URL/execute_current_stage" -H "Content-Type: application/json" -d '{"stage_payload": {}}')
echo "stage0: ${resp:0:160}..."
pk=$(echo "$resp" | python3 -c "import sys,json;print(json.loads(sys.stdin.read())['stage_result']['public key'])")
probe="0x$(python3 -c "import os;print(os.urandom(33).hex())")"
oresp=$(curl -s -X POST "$SERVER_URL/oracle_query" -H "Content-Type: application/json" -d "{\"oracle_type\": \"sign\", \"arguments\": {\"message\": \"$probe\"}}")
echo "oracle: ${oresp:0:120}..."
probe_sig=$(echo "$oresp" | python3 -c "import sys,json;d=json.loads(sys.stdin.read());r=d.get('oracle_result') or d;print(r.get('signature',''))")
out=$(uv run python3 /app/forge.py "$pk" "$probe_sig" "$probe")
echo "$out"
message=$(echo "$out" | grep '^message:' | awk '{print $2}')
signature=$(echo "$out" | grep '^signature:' | awk '{print $2}')
resp=$(curl -s -X POST "$SERVER_URL/execute_current_stage" -H "Content-Type: application/json" -d "{\"stage_payload\": {\"message\": \"$message\", \"signature\": \"$signature\"}}")
echo "stage1: $resp"
won=$(echo "$resp" | python3 -c "import sys,json;print(json.loads(sys.stdin.read())['stage_result'].get('Game won','No'))")
[ "$won" = "Yes" ] && echo "SUCCESS: forgery accepted" || echo "FAILURE: forgery rejected"
ATTACK_EOF
chmod +x /app/attack.sh

echo "SignatureForgeryGame" > /app/security_game_choice.txt
echo "solve.sh finished."
