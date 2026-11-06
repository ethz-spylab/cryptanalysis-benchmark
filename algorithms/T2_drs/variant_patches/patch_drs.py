#!/usr/bin/env python3
"""Scale-down patcher for DRS (Diagonal Reduction Signature).

Rewrites the lattice dimension _DIM_ and its co-dependent secret-row constants
in the level-I header `DRS/Reference_Implementation/API_H/api.h.128` (the file
build_cli.sh copies to `api.h`), plus the buffer-size macros derived from _DIM_.

The buffer-size macros (CRYPTO_PUBLICKEYBYTES / CRYPTO_SECRETKEYBYTES /
CRYPTO_BYTES / MSG_VECTOR_BYTES) are the *exact* serialized lengths produced by
char_key_conv.h for the chosen parameter set (the CLI rejects keys/signatures
whose byte length differs), so they MUST track _DIM_ and the row constants. The
bit-width macros _BITS_D_BD (10) and _SIZE_P_COEF (48) are kept at their shipped
values: both are used symmetrically by the (de)serializers and stay large enough
to hold every coefficient for the reduced dimensions, so they need no change.

Usage:
  patch_drs.py <api.h.128 path> DIM DBOUND NB_ONES NB_B B_VAL PK SK SIG MSG

Fails loudly (non-zero exit) if any expected #define is not found / not changed.
"""

import re
import sys


def replace_define(text, name, value):
    """Replace the value of `#define <name> ...` with (<value>).

    Handles both the parenthesized form `#define _DIM_ (912)` and the bare
    numeric form `#define CRYPTO_PUBLICKEYBYTES 5094433` used in api.h.128.
    Asserts exactly one substitution happened.
    """
    pattern = re.compile(r"(#define\s+" + re.escape(name) + r"\s+)(\([^)\n]*\)|-?\d+)")
    new_text, n = pattern.subn(r"\g<1>(" + str(value) + ")", text)
    if n != 1:
        sys.stderr.write(
            f"patch_drs.py: expected exactly 1 match for #define {name}, got {n}\n"
        )
        sys.exit(1)
    return new_text


def main():
    if len(sys.argv) != 11:
        sys.stderr.write(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    (dim, dbound, nb_ones, nb_b, b_val, pk, sk, sig, msg) = (
        int(x) for x in sys.argv[2:11]
    )

    with open(path, "r") as f:
        text = f.read()
    original = text

    # Primary knob + co-dependent secret-row structure (diagonal dominance:
    # _NB_B_*_B_VAL_ + _NB_ONES_ < _D_BOUND_, with _D_BOUND_ == _DIM_).
    text = replace_define(text, "_DIM_", dim)
    text = replace_define(text, "_D_BOUND_", dbound)
    text = replace_define(text, "_NB_ONES_", nb_ones)
    text = replace_define(text, "_NB_B_", nb_b)
    text = replace_define(text, "_B_VAL_", b_val)

    # Buffer-size macros recomputed for the new _DIM_ (exact serialized lengths).
    text = replace_define(text, "CRYPTO_PUBLICKEYBYTES", pk)
    text = replace_define(text, "CRYPTO_SECRETKEYBYTES", sk)
    text = replace_define(text, "CRYPTO_BYTES", sig)
    text = replace_define(text, "MSG_VECTOR_BYTES", msg)

    if text == original:
        sys.stderr.write("patch_drs.py: no changes made (refusing silent no-op)\n")
        sys.exit(1)

    with open(path, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
