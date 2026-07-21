"""Pure-Python ports of the LOTUS-128 pack routines (from pack.c), byte-exact.

Used by the key-recovery attack to (a) build malformed ciphertexts to feed the
decapsulate oracle (pack_ct) and (b) serialize the recovered secret matrix S in
the exact CLI format (pack_sk) so the submitted private key matches byte-for-byte.

Parameters (lotus128):  DIM=576, PT=128, MOD=8192 (q=2^13), LOG2_MOD=13.
ct has DIM+PT = 704 elements = 5*128 + 64.
sk (S only) has DIM*PT = 73728 elements -> pack_128dg, 6 bits each.
"""
import struct

DIM = 576
PT = 128
MOD = 8192
LOG2 = 13

MSB = 0x8000
MS3B = 0xE000
LOWER8 = 0x00FF


def _u16le(vals):
    return struct.pack("<%dH" % len(vals), *[v & 0xFFFF for v in vals])


def _from_u16le(b):
    return list(struct.unpack("<%dH" % (len(b) // 2), b))


def pack_128elems(op):
    """Pack 128 13-bit elems -> 208 bytes (104 U16). Mirror of pack.c."""
    n = 16
    ptr = [0] * 104
    for i in range(n):
        ptr[0 * n + i] = op[0 * n + i] | ((op[6 * n + i] << 3) & MS3B)
    for i in range(n):
        ptr[1 * n + i] = op[1 * n + i] | ((op[6 * n + i] << 6) & MS3B)
    for i in range(n):
        ptr[2 * n + i] = op[2 * n + i] | ((op[6 * n + i] << 9) & MS3B)
    for i in range(n):
        ptr[3 * n + i] = op[3 * n + i] | ((op[6 * n + i] << 12) & MS3B)
    for i in range(n):
        ptr[4 * n + i] = op[4 * n + i] | (((op[6 * n + i] << 15) | (op[7 * n + i] << 2)) & MS3B)
    for i in range(n):
        ptr[5 * n + i] = op[5 * n + i] | ((op[7 * n + i] << 5) & MS3B)
    for i in range(n // 2):
        ptr[6 * n + i] = (op[7 * n + i] & LOWER8) | ((op[7 * n + n // 2 + i] & LOWER8) << 8)
    return _u16le(ptr)


def pack_64elems(op):
    """Pack 64 13-bit elems -> 104 bytes (52 U16)."""
    n = 8
    ptr = [0] * 52
    for i in range(n):
        ptr[0 * n + i] = op[0 * n + i] | ((op[6 * n + i] << 3) & MS3B)
    for i in range(n):
        ptr[1 * n + i] = op[1 * n + i] | ((op[6 * n + i] << 6) & MS3B)
    for i in range(n):
        ptr[2 * n + i] = op[2 * n + i] | ((op[6 * n + i] << 9) & MS3B)
    for i in range(n):
        ptr[3 * n + i] = op[3 * n + i] | ((op[6 * n + i] << 12) & MS3B)
    for i in range(n):
        ptr[4 * n + i] = op[4 * n + i] | (((op[6 * n + i] << 15) | (op[7 * n + i] << 2)) & MS3B)
    for i in range(n):
        ptr[5 * n + i] = op[5 * n + i] | ((op[7 * n + i] << 5) & MS3B)
    for i in range(n // 2):
        ptr[6 * n + i] = (op[7 * n + i] & LOWER8) | ((op[7 * n + n // 2 + i] & LOWER8) << 8)
    return _u16le(ptr)


def pack_ct(ct):
    """ct: list of DIM+PT (=704) U16. Returns _LOTUS_PACK_CT_BYTES bytes."""
    out = bytearray()
    idx = 0
    full = (DIM + PT) // 128  # 5
    for _ in range(full):
        out += pack_128elems(ct[idx:idx + 128])
        idx += 128
    out += pack_64elems(ct[idx:idx + 64])  # remaining 64
    return bytes(out)


def pack_128dg(op):
    """Pack 128 discrete-Gaussian samples (6 bits each) -> 96 bytes (48 U16)."""
    n = 16
    ptr = [0] * 48
    for i in range(n):
        ptr[0 * n + i] = ((op[0 * n + i] & 0x3F)
                          | ((op[1 * n + i] & 0x3F) << 6)
                          | ((op[2 * n + i] & 0x3F) << 12)) & 0xFFFF
    for i in range(n):
        ptr[1 * n + i] = (((op[2 * n + i] & 0x3F) >> 4)
                          | ((op[3 * n + i] & 0x3F) << 2)
                          | ((op[4 * n + i] & 0x3F) << 8)
                          | ((op[5 * n + i] & 0x3F) << 14)) & 0xFFFF
    for i in range(n):
        ptr[2 * n + i] = (((op[5 * n + i] & 0x3F) >> 2)
                          | ((op[6 * n + i] & 0x3F) << 4)
                          | ((op[7 * n + i] & 0x3F) << 10)) & 0xFFFF
    return _u16le(ptr)


def pack_sk(S):
    """S: list of DIM*PT (=73728) U16 in [0, q). Returns _LOTUS_PACK_PRVKEY_BYTES bytes."""
    out = bytearray()
    idx = 0
    n = (DIM * PT) // 128
    for _ in range(n):
        out += pack_128dg(S[idx:idx + 128])
        idx += 128
    return bytes(out)
