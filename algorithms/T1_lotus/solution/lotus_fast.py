"""Batched multi-coordinate recovery for the LOTUS-128 failure-leak attack.

The decapsulate oracle leaks ss = SHA512(sigma || 0x01)[:16], where sigma is the
full 128-coordinate (16-byte) decrypted message. The naive recovery
(lotus_recover.recover_S) uses this as a *1-bit* oracle (ss == H(0)?) and spends
2 queries per coordinate per bit, costing ~480k queries.

This module instead reads G coordinates per query: with all non-target
coordinates pinned to a known-zero baseline, sigma ranges over a small set, so a
single ss identifies the G target bits by matching against a precomputed table
of candidate hashes. Because the target coordinates occupy fixed byte positions
and the rest are zero, the candidate->hash tables depend only on the (fixed)
coordinate partition, so they are precomputed ONCE and reused across every row
and bit. This cuts the query count ~11x (to ~43k) while recovering the exact
same secret matrix S as recover_S (verified bit-for-bit).

The per-coordinate update logic is identical to lotus_recover.recover_S; only the
oracle access is batched, which does not change any recovered value (each
coordinate's b1/b2 outcome is independent of the others within a bit level).
"""
import hashlib

from lotus_pack import PT, MOD
from lotus_recover import H_zero_sigma, build_ct_hex

DIM_BITS = 13           # log2(MOD); MOD = 2^13 = 8192
PT_BYTES = PT // 8      # 16
Q8 = MOD // 8           # 1024 = q/8
G = 16                  # coordinates read per probe (2 bytes / group, 2^16 table)


def _ss_for_sigma(sigma_bytes):
    return hashlib.sha512(bytes(sigma_bytes) + b"\x01").digest()[:PT_BYTES]


def build_group_tables(g_size=G):
    """Partition the PT coordinates into fixed groups of g_size and, for each
    group, map every leaked ss (over candidate bit-patterns of that group, with
    all other coordinates zero) back to its bit-pattern. Reused for all queries."""
    groups = [list(range(s, min(s + g_size, PT))) for s in range(0, PT, g_size)]
    tables = []
    for coords in groups:
        gw = len(coords)
        tab = {}
        for pat in range(1 << gw):
            sig = bytearray(PT_BYTES)
            for t in range(gw):
                if (pat >> t) & 1:
                    c = coords[t]
                    sig[c >> 3] |= (1 << (c & 7))
            tab[_ss_for_sigma(sig)] = pat
        tables.append((coords, tab))
    return tables


def recover_S_fast(oracle, tables=None, progress=None, max_rows=None):
    """Recover the LOTUS secret matrix S (list of DIM*PT ints in [0, q)).

    `oracle(ct_hex) -> bytes16` queries the decapsulate oracle. Returns
    (S, fallback_count); fallback_count > 0 means some group probe failed to
    match a precomputed hash and was re-probed per coordinate (should be 0)."""
    if tables is None:
        tables = build_group_tables(G)
    from lotus_pack import DIM
    Hz = H_zero_sigma()
    nrows = DIM if max_rows is None else max_rows
    guess = [0] * (DIM * PT)
    fallbacks = 0
    for i in range(nrows):
        c2 = [0] * PT
        for k in range(DIM_BITS - 1):
            c1 = [0] * DIM
            c1[i] = 1 << k
            for j in range(PT):
                c2[j] = 2 * c2[j]
            # baseline skip check (global +/- q8): if the whole row decodes to 0
            # under both shifts, this bit level contributes nothing.
            z1 = oracle(build_ct_hex(c1, [(c2[j] + Q8) % MOD for j in range(PT)])) == Hz
            z2 = oracle(build_ct_hex(c1, [(c2[j] + MOD - Q8) % MOD for j in range(PT)])) == Hz
            if z1 and z2:
                continue
            b1 = [0] * PT
            b2 = [0] * PT
            for coords, tab in tables:
                ctA = [c2[w] % MOD for w in range(PT)]
                for c in coords:
                    ctA[c] = (c2[c] + Q8) % MOD
                ssA = oracle(build_ct_hex(c1, ctA))
                ctB = [c2[w] % MOD for w in range(PT)]
                for c in coords:
                    ctB[c] = (c2[c] + MOD - Q8) % MOD
                ssB = oracle(build_ct_hex(c1, ctB))
                pA = tab.get(ssA)
                pB = tab.get(ssB)
                if pA is None or pB is None:
                    # Robust fallback: re-probe this group one coordinate at a
                    # time against the all-zero reference (the original method).
                    fallbacks += 1
                    for c in coords:
                        ct = [c2[w] % MOD for w in range(PT)]
                        ct[c] = (c2[c] + Q8) % MOD
                        b1[c] = int(oracle(build_ct_hex(c1, ct)) != Hz)
                        ct = [c2[w] % MOD for w in range(PT)]
                        ct[c] = (c2[c] + MOD - Q8) % MOD
                        b2[c] = int(oracle(build_ct_hex(c1, ct)) != Hz)
                else:
                    for t, c in enumerate(coords):
                        b1[c] = (pA >> t) & 1
                        b2[c] = (pB >> t) & 1
            for j in range(PT):
                idx = i * PT + j
                if b1[j] and not b2[j]:
                    guess[idx] = guess[idx] * 2 + 1
                    c2[j] += MOD - Q8
                elif (not b1[j]) and b2[j]:
                    guess[idx] = guess[idx] * 2 - 1
                    c2[j] += Q8
                elif (not b1[j]) and (not b2[j]):
                    guess[idx] = guess[idx] * 2
                else:
                    raise RuntimeError(f"unexpected both-set at i={i} j={j} k={k}")
        if progress and i % 16 == 0:
            progress(i)
    S = [(g // 2) % MOD for g in guess]
    return S, fallbacks


Q4 = MOD // 4  # q/4 = 2048; the lower decode boundary


def _extended_coord_search(oracle, c1, j, saturate, B, BMAX, Hz):
    """Resolve a single coordinate whose value saturated at +/-B in the batched
    threshold search (i.e. |S[i][j]| >= B). Probes coordinate j alone (all other
    coordinates pinned to sigma=0) and binary-searches g via the all-zero test
    ss == H(0): sigma_j = 1 iff S[i][j] >= g. Returns the exact value."""
    # c2 = 0 pins a coordinate to sigma=0 for ANY |S| << q/4 (decode(S) = 0),
    # robust regardless of magnitude.
    base = [0] * PT
    if saturate == B:
        lo, hi = B, BMAX
    else:
        lo, hi = -BMAX, -B
    while lo < hi:
        mid = (lo + hi + 1) // 2
        c2 = base[:]
        c2[j] = (Q4 - mid) % MOD
        if oracle(build_ct_hex(c1, c2)) != Hz:  # sigma_j = 1 => S >= mid
            lo = mid
        else:
            hi = mid - 1
    return lo


def recover_S_threshold(oracle, tables=None, B=7, BMAX=63, progress=None,
                        max_rows=None):
    """Value-based recovery of the LOTUS secret matrix S — far fewer queries than
    the bit-by-bit recover_S / recover_S_fast.

    With c1 = e_i (so the recovered message is t = c2 + S[i][:] mod q) and the
    decode sigma_j = 1 iff t[j] in [q/4, 3q/4), setting c2[j] = q/4 - g makes
    sigma_j = 1 iff S[i][j] >= g. Each query is therefore a per-coordinate
    threshold comparison. We binary-search ALL coordinates of a row in parallel
    over the small range [-B, B] (the LOTUS-128 secret is a narrow discrete
    Gaussian, observed |S| <= 5), reading G coordinates per query from the
    precomputed hash tables with the rest pinned to sigma=0. This needs only
    ceil(log2(2B+1)) rounds and NO baseline/bit-level probing.

    A coordinate that saturates at +/-B (|S| > B, vanishingly rare) is resolved
    exactly by _extended_coord_search up to +/-BMAX, so the result is correct for
    any key. Returns (S, n_extended)."""
    from lotus_pack import DIM
    if tables is None:
        tables = build_group_tables(20)
    Hz = H_zero_sigma()
    nrows = DIM if max_rows is None else max_rows
    rounds = (2 * B + 1).bit_length()  # ceil(log2(2B+1))
    # c2 = 0 pins a coordinate to sigma=0 for ANY |S| << q/4 (decode(S) = 0), so
    # out-of-range coordinates (|S| > B) don't corrupt other groups' batched reads.
    pin_row = [0] * PT
    S = [0] * (DIM * PT)
    n_extended = 0
    for i in range(nrows):
        c1 = [0] * DIM
        c1[i] = 1
        lo = [-B] * PT
        hi = [B] * PT
        for _ in range(rounds):
            mid = [(lo[j] + hi[j] + 1) // 2 for j in range(PT)]
            for coords, tab in tables:
                c2 = pin_row[:]
                for c in coords:
                    c2[c] = (Q4 - mid[c]) % MOD
                pat = tab.get(oracle(build_ct_hex(c1, c2)))
                if pat is None:
                    raise RuntimeError(f"no hash match at row {i}")
                for t, c in enumerate(coords):
                    if (pat >> t) & 1:
                        lo[c] = mid[c]
                    else:
                        hi[c] = mid[c] - 1
        for j in range(PT):
            v = lo[j]
            if v == B or v == -B:
                v = _extended_coord_search(oracle, c1, j, v, B, BMAX, Hz)
                n_extended += 1
            S[i * PT + j] = v % MOD
        if progress and i % 16 == 0:
            progress(i)
    return S, n_extended
