#!/usr/bin/env python3
"""Patch McNie's GF(2^m) extension degree _m (the single rank-metric security knob).

McNie is a code-based rank-metric PKE/KEM whose security rests on Rank Syndrome
Decoding over GF(2^m). The extension degree m = `_m` in gf.c sets the field size
and is the clean monotone difficulty dial: the structural QRCSP/Gaborit attack
cost rises ~linearly in the exponent with m (see
algorithm_scaling_down/nist_pqc/mcnie.txt). blk=31 (n=3*blk=93, k=62), LRPC
weight d=3 and error rank r=5 are held fixed; LRPC correctness needs r*d <= m
(r*d = 15), so any band value m >= 29 still decodes correctly.

Two coupled edits are required, both confined to the 3Q_128_1 param dir:

  * gf.c   : `const short _m = 37;` -> `const short _m = <m>;`
      The chosen m MUST have a nonzero `base_poly[m]` entry (the precomputed
      irreducible polynomial over GF(2)); otherwise the field modulus is zero and
      arithmetic breaks. Below the shipped 37, the valid degrees are {29,30,31,35}.

  * crypt.h: `#define CIPHER_BYTES 579` -> the real one-block ciphertext length for
      this m. The upstream crypto computes every byte length at runtime from _m, but
      the CLI's I/O contract hardcodes the m=37 size: `encrypt` prints the real
      runtime length `clen` while `decrypt` demands exactly CIPHER_BYTES, so without
      this edit the round-trip fails a length check. The serialized one-block
      ciphertext is `(_m*(2n-k)+7)/8 + CONST_LEN` bytes (crypt.c crypto_encrypt;
      2n-k = 124, CONST_LEN = 5), i.e. CIPHER_BYTES(m) = (m*124+7)//8 + 5
      (verified: 29->455, 31->486, 35->548, 37->579, matching encrypt's output).
      The pk/sk/MESSAGE_BYTES macros stay at the m=37 values: for m<37 the real
      objects are strictly smaller, so those macros are safe upper bounds (buffer
      sizes / print lengths) used identically by generation and consumption, and
      the upstream crypto never reads them.

Usage: patch_mcnie.py <path/to/3Q_128_1 dir> <m>

Fails loudly (non-zero exit) if either expected substitution makes zero changes,
so a botched patch can never silently yield an unweakened variant.
"""
import os
import re
import sys

# Degrees below the shipped 37 with a nonzero base_poly[m] entry (verified in gf.c).
VALID_DEGREES = {29, 30, 31, 35}

# Public code geometry, held fixed (blk=31 -> n=3*blk=93, k=2*blk=62).
N = 93
K = 62
CONST_LEN = 5  # length of the trailing y5/const bytes appended to each ciphertext block


def cipher_bytes(m: int) -> int:
    # One serialized ciphertext block, per crypt.c crypto_encrypt:
    #   cip_len = (_m*(2n-k)+7) >> 3 ; cip_len += CONST_LEN
    return (m * (2 * N - K) + 7) // 8 + CONST_LEN


def patch_one(path, pattern, replacement, label):
    with open(path, "rb") as f:
        data = f.read()
    new_data, n = pattern.subn(replacement, data)
    if n == 0:
        sys.stderr.write(f"FATAL: pattern for {label} not found in {path}; nothing patched\n")
        sys.exit(1)
    if n != 1:
        sys.stderr.write(f"FATAL: pattern for {label} matched {n} times, expected exactly 1\n")
        sys.exit(1)
    with open(path, "wb") as f:
        f.write(new_data)


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_mcnie.py <path/to/3Q_128_1 dir> <m>\n")
        return 2

    param_dir = sys.argv[1]
    mval = int(sys.argv[2])

    if mval not in VALID_DEGREES:
        sys.stderr.write(
            f"FATAL: m={mval} has no valid base_poly entry below the shipped 37 "
            f"(allowed: {sorted(VALID_DEGREES)})\n"
        )
        return 2

    gf_path = os.path.join(param_dir, "gf.c")
    crypt_h = os.path.join(param_dir, "crypt.h")
    for p in (gf_path, crypt_h):
        if not os.path.isfile(p):
            sys.stderr.write(f"FATAL: expected source file missing: {p}\n")
            return 1

    # gf.c: set the GF(2^m) extension degree.
    patch_one(
        gf_path,
        re.compile(rb"const\s+short\s+_m\s*=\s*\d+\s*;"),
        b"const short _m = %d;" % mval,
        "gf.c const short _m",
    )

    # crypt.h: match the CLI ciphertext-length contract to the real per-m length.
    patch_one(
        crypt_h,
        re.compile(rb"#define\s+CIPHER_BYTES\s+\d+"),
        b"#define CIPHER_BYTES   %d" % cipher_bytes(mval),
        "crypt.h #define CIPHER_BYTES",
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
