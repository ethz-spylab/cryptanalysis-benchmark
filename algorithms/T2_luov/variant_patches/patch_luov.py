#!/usr/bin/env python3
"""Scale down LUOV's MQ system size (OIL_VARS = m, VINEGAR_VARS = v) for a variant.

LUOV = Lifted Unbalanced Oil & Vinegar (multivariate signature). The shipped
CryptanalysisBench task is the NIST round-1 set luov-8-63-256: field GF(2^8)
(FIELD_SIZE=8, lifted from GF(2)), m = OIL_VARS = 63 equations/oil-variables,
v = VINEGAR_VARS = 256 vinegar variables, n = m + v = 319 total variables.

The dominant attack is direct algebraic forgery: fix n-m of the n variables and
solve the remaining determined system of m quadratic equations in m unknowns over
GF(2^8) (Groebner / exhaustive). Its cost is governed by the number of equations
m = OIL_VARS, so reducing m (with v scaled to preserve the unbalanced v > m UOV
structure so key-recovery does not become the cheaper path) is the scaling knob.

Everything downstream is derived from OIL_VARS / VINEGAR_VARS by formula:
  * parameters.h: VARS = OIL_VARS+VINEGAR_VARS,
                  STORED_COLS_OF_P = OIL_VARS*(OIL_VARS+1)/2
  * api.h:        CRYPTO_SECRETKEYBYTES = 32                (seed only)
                  CRYPTO_PUBLICKEYBYTES = 32 + ceil(STORED_COLS_OF_P*OIL_VARS/8)
                  CRYPTO_BYTES          = VARS*(FIELD_SIZE/8)
so patching the two primary macros in parameters.h is sufficient; api.h and the
Bitcontainer / LinearAlgebra buffers all re-derive at compile time. (The only
structural branch is Bitcontainer's `#if OIL_VARS > 64`; every band keeps
m <= 64, matching the shipped m=63 code path.)

The field GF(2^8) arithmetic tables (F8Field.c) and the SHAKE128 expansion stay
valid because FIELD_SIZE and SHAKENUM are untouched.

Usage:
    patch_luov.py <path/to/parameters.h> <m/OIL_VARS> <v/VINEGAR_VARS>

Self-checks: the active shipped tokens `OIL_VARS 63` and `VINEGAR_VARS 256` must
each be present exactly once (they are unique to the selected parameter set; the
other sets sit inside /* ... */ comment blocks), and each replacement must change
exactly one occurrence. Fails loudly otherwise so generation cannot silently ship
an unweakened variant.
"""
import sys

# Shipped active values of the selected luov-8-63-256 parameter set.
BASE_M = 63
BASE_V = 256


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: patch_luov.py <parameters.h> <m/OIL_VARS> <v/VINEGAR_VARS>")
    path = sys.argv[1]
    m = int(sys.argv[2])
    v = int(sys.argv[3])

    if not (0 < m < BASE_M):
        sys.exit(f"ERROR: m={m} must satisfy 0 < m < {BASE_M} (strictly weaker than base)")
    if not (0 < v < BASE_V):
        sys.exit(f"ERROR: v={v} must satisfy 0 < v < {BASE_V} (strictly weaker than base)")
    if v <= m:
        sys.exit(f"ERROR: v={v} must exceed m={m} to keep the unbalanced UOV structure valid")
    if m > 64:
        sys.exit(f"ERROR: m={m} > 64 would change the Bitcontainer code path; keep m <= 64")

    with open(path, "r") as f:
        text = f.read()

    old_oil = f"OIL_VARS {BASE_M}"
    old_vin = f"VINEGAR_VARS {BASE_V}"
    new_oil = f"OIL_VARS {m}"
    new_vin = f"VINEGAR_VARS {v}"

    n_oil = text.count(old_oil)
    n_vin = text.count(old_vin)
    if n_oil != 1:
        sys.exit(f"ERROR: expected exactly 1 occurrence of '{old_oil}' in {path}, found {n_oil}")
    if n_vin != 1:
        sys.exit(f"ERROR: expected exactly 1 occurrence of '{old_vin}' in {path}, found {n_vin}")

    text = text.replace(old_oil, new_oil, 1)
    text = text.replace(old_vin, new_vin, 1)

    if text.count(new_oil) != 1 or text.count(new_vin) != 1:
        sys.exit(f"ERROR: post-patch verification failed in {path}")

    with open(path, "w") as f:
        f.write(text)

    # Report derived sizes (FIELD_SIZE=8 => 1 byte / field element).
    n = m + v
    stored_cols = m * (m + 1) // 2
    pk = 32 + ((stored_cols * m) + 7) // 8
    sig = n * (8 // 8)
    print(f"patched {path}: m/OIL_VARS={m} v/VINEGAR_VARS={v} "
          f"n={n} | CRYPTO_PUBLICKEYBYTES={pk} CRYPTO_BYTES(sig)={sig} "
          f"CRYPTO_SECRETKEYBYTES=32")


if __name__ == "__main__":
    main()
