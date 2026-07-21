"""LOTUS-128 KEM private-key recovery against the decapsulate oracle.

Implements the Lepoint failure-leak attack (OFFICIAL COMMENT: LOTUS, Dec 2017)
purely in Python, talking to a decapsulate oracle that returns
    ss = csym XOR H(sigma)
even when verification fails. We set csym = 0, so ss = first 16 bytes of
SHA-512(sigma || 0x01). Crafted ciphertexts c1 = 2^k * e_i with c2 +/- q/8
recover the secret matrix S exactly, row by row.

`oracle(ct_hex)` must be supplied by the caller and return the 16-byte shared
secret as `bytes` (or None on a hard failure). This module is transport-agnostic
so it can be driven by a real game controller or a local mock.
"""
import hashlib

from lotus_pack import DIM, PT, MOD, pack_ct, pack_sk

CT_PACK_BYTES = (DIM + PT) * 13 // 8  # 1144


def H_zero_sigma():
    """ss expected when sigma == 0 and csym == 0: SHA-512(0^16 || 0x01)[:16]."""
    return hashlib.sha512(bytes(16) + b"\x01").digest()[:16]


def build_ct_hex(c1, c2):
    """c1: list[DIM] U16, c2: list[PT] U16. Returns hex ct (csym = 0)."""
    ct = [v & 0xFFFF for v in c1] + [v & 0xFFFF for v in c2]
    packed = pack_ct(ct)
    full = packed + bytes(16)  # csym = 0
    return "0x" + full.hex()


def recover_S(oracle, progress=None):
    """Recover the full secret matrix S (list of DIM*PT ints in [0, q)).

    `oracle(ct_hex) -> bytes16` queries the decapsulate oracle.
    """
    Hz = H_zero_sigma()
    q8 = MOD // 8
    guess = [0] * (DIM * PT)

    for i in range(DIM):
        c2 = [0] * PT
        for k in range(13 - 1):  # k = 0 .. 11
            c1 = [0] * DIM
            c1[i] = 1 << k
            # probe all coords with +q/8 (after doubling baseline)
            for j in range(PT):
                c2[j] = 2 * c2[j]
            ct = [(c2[j] + q8) % MOD for j in range(PT)]
            ss1 = oracle(build_ct_hex(c1, ct))
            z1 = (ss1 == Hz)
            ct = [(c2[j] + MOD - q8) % MOD for j in range(PT)]
            ss2 = oracle(build_ct_hex(c1, ct))
            z2 = (ss2 == Hz)
            if z1 and z2:
                continue
            # coordinate by coordinate
            for j in range(PT):
                ct = [c2[w] % MOD for w in range(PT)]
                ct[j] = (c2[j] + q8) % MOD
                b1 = (oracle(build_ct_hex(c1, ct)) != Hz)
                ct[j] = (c2[j] + MOD - q8) % MOD
                b2 = (oracle(build_ct_hex(c1, ct)) != Hz)
                idx = i * PT + j
                if b1 and not b2:
                    guess[idx] = guess[idx] * 2 + 1
                    c2[j] += MOD - q8
                elif not b1 and b2:
                    guess[idx] = guess[idx] * 2 - 1
                    c2[j] += q8
                elif not b1 and not b2:
                    guess[idx] = guess[idx] * 2
                else:
                    raise RuntimeError(f"unexpected both-nonzero at i={i} j={j} k={k}")
        if progress and i % 32 == 0:
            progress(i)

    # S = floor(guess / 2), then reduce mod q
    S = []
    for g in guess:
        sv = g // 2  # Python // is floor division (works for negatives)
        S.append(sv % MOD)
    return S


def serialize_sk(S, pk_bytes):
    """Build the full CLI secret-key bytes: pack_sk(S) || packed public key."""
    return pack_sk(S) + pk_bytes
