#!/usr/bin/env python3
"""Scale down the DME-KEM field extension degree e (default 48) to a smaller
value, per algorithm_scaling_down/nist_pqc/dme.txt.

The field degree e = 48 is hard-wired across the reference tree as the literal
48 (Fq loop bound / `1<<48` mask / `% 48` Frobenius reductions), as 96 = 2*e
(Fq2 order exponent) and 144 = 3*e (Fq3 order exponent), and through the field
modulus `min_poly`.  This script rewrites every site for a new degree e:

  * dme.c, setup/find_min_poly.c, setup/find_m1_m2.c : Fq arithmetic loop bound
    48 -> e, mask `1<<48` -> `1<<e`, Frobenius `% 48` -> `% e`.
  * setup/find_best_exps.c : `% 96` -> `% 2e`, `% 144` -> `% 3e`, and the
    `bigint_powi(q1m1,2,48)/(q2m1,2,96)/(q3m1,2,144)` field-order exponents.
  * setup/find_min_poly.c : the `min_poly` constant -> an irreducible binary
    polynomial of degree e.
  * setup/find_min_poly.c, setup/find_m1_m2.c : `fq_rnd()` masked to e bits so
    the randomly generated field constants / fixed plaintexts are genuine
    elements of F_{2^e} (high bits would corrupt the Fq arithmetic).
  * dme.c parse_fq_elem : every field element read from a serialized buffer is
    reduced to its low e bits, so the random secret-key matrix entries (and any
    other parsed value) are genuine elements of F_{2^e}.  Without this, the
    random 48-bit secret-key entries are not field elements and fq_inv /
    fq_matrix_inverse misbehave (the keypair routine hangs).
  * dme.c crypto_kem_enc : the random shared-secret plaintext elements are
    reduced into F_{2^e} (low e bits) before encryption, and the shared secret
    is re-derived from the reduced plaintext so decapsulation recovers exactly
    the same bytes.  Without this the random 48-bit plaintext elements are not
    valid field elements and the KEM does not round-trip.

The 6-byte (48-bit) serialization and the api.h key/ciphertext sizes are left
unchanged for any e <= 48 (the unused high bits simply stay zero).

Usage:  patch_dme.py <Reference_Implementation_dir> <e> <min_poly_hex>
e.g.    patch_dme.py /tmp/x/DME/Reference_Implementation 21 0x200005
"""

import sys


def sub(text, old, new, count, path):
    n = text.count(old)
    if n != count:
        raise SystemExit(
            f"FATAL [{path}]: expected {count} occurrences of {old!r}, found {n}"
        )
    return text.replace(old, new)


def patch_file(path, edits):
    with open(path) as f:
        text = f.read()
    for old, new, count in edits:
        text = sub(text, old, new, count, path)
    with open(path, "w") as f:
        f.write(text)


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    ref = sys.argv[1].rstrip("/")
    e = int(sys.argv[2])
    min_poly = sys.argv[3]
    if not (1 <= e <= 48):
        raise SystemExit(f"FATAL: e={e} out of range (1..48)")
    e2, e3 = 2 * e, 3 * e

    # ---- dme.c -----------------------------------------------------------
    enc_old = (
        "  parse_text(pt_q, pt);\n"
        "  if (parse_pkey(&pkey, pk) || fq_encrypt(ct_q, pt_q, &pkey)) return -1;"
    )
    enc_new = (
        "  parse_text(pt_q, pt);\n"
        "  /* DME scaling-down (e<48): reduce each plaintext element into Fq\n"
        "     (keep only the low %d bits) so it is a valid field element; high\n"
        "     bits would otherwise corrupt the Fq arithmetic. Re-derive the\n"
        "     shared secret from the reduced plaintext so decapsulation recovers\n"
        "     exactly these bytes. */\n"
        "  for (i=0; i<6; i++) pt_q[i] &= ((UINT64_C(1) << %d) - 1);\n"
        "  serialize_text(pt, pt_q);\n"
        "  for (i=0; i<11; i++)\n"
        "  {\n"
        "    ss[i] = pt[i];\n"
        "    ss[i+11] = pt[i+12];\n"
        "    ss[i+22] = pt[i+24];\n"
        "  }\n"
        "  if (parse_pkey(&pkey, pk) || fq_encrypt(ct_q, pt_q, &pkey)) return -1;"
    ) % (e, e)
    patch_file(
        ref + "/dme.c",
        [
            ("for (i=0; i<48; i++)", f"for (i=0; i<{e}; i++)", 1),
            ("(UINT64_C(1) << 48)", f"(UINT64_C(1) << {e})", 3),
            ("% 48)", f"% {e})", 16),
            # Reduce every parsed field element (notably the random secret-key
            # matrix entries) into F_{2^e}.  parse_fq_elem is the only "return a;".
            ("  return a;\n}", f"  return a & ((UINT64_C(1) << {e}) - 1);\n}}", 1),
            (enc_old, enc_new, 1),
        ],
    )

    # ---- setup/find_min_poly.c ------------------------------------------
    patch_file(
        ref + "/setup/find_min_poly.c",
        [
            ("UINT64_C(0x1000018000003)", f"UINT64_C({min_poly})", 1),
            ("for (i=0; i<48; i++)", f"for (i=0; i<{e}; i++)", 3),
            ("(UINT64_C(1) << 48)", f"(UINT64_C(1) << {e})", 3),
            ("  return a;\n}", f"  return a & ((UINT64_C(1) << {e}) - 1);\n}}", 1),
        ],
    )

    # ---- setup/find_best_exps.c -----------------------------------------
    patch_file(
        ref + "/setup/find_best_exps.c",
        [
            ("% 96)", f"% {e2})", 6),
            ("rand() % 96", f"rand() % {e2}", 6),
            ("bigint_powi(q2m1, 2, 96)", f"bigint_powi(q2m1, 2, {e2})", 1),
            ("% 144)", f"% {e3})", 4),
            ("rand() % 144", f"rand() % {e3}", 4),
            ("bigint_powi(q3m1, 2, 144)", f"bigint_powi(q3m1, 2, {e3})", 1),
            ("bigint_powi(q1m1, 2, 48)", f"bigint_powi(q1m1, 2, {e})", 1),
        ],
    )

    # ---- setup/find_m1_m2.c ---------------------------------------------
    patch_file(
        ref + "/setup/find_m1_m2.c",
        [
            ("for (i=0; i<48; i++)", f"for (i=0; i<{e}; i++)", 1),
            ("(UINT64_C(1) << 48)", f"(UINT64_C(1) << {e})", 3),
            ("% 48)", f"% {e})", 16),
            ("  return a;\n}", f"  return a & ((UINT64_C(1) << {e}) - 1);\n}}", 1),
        ],
    )

    print(
        f"patch_dme.py: set field degree e={e}, min_poly={min_poly} (2e={e2}, 3e={e3})"
    )


if __name__ == "__main__":
    main()
