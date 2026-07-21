#!/usr/bin/env python3
"""Spook medium variant patch: peel one extra inner-round.

The base sed-patch in generate_variants.sh has already lowered the loop
bound to NS = 1 in clyde128_encrypt and clyde128_decrypt. To realise the
spec's "R = 3" medium band (NS = 1.5) we additionally:

* In `clyde128_encrypt`, after the per-step loop terminates, run one extra
  half-step: sbox_layer + lbox_layer + add_rc(state, 2*NS).
* In `clyde128_decrypt`, before the per-step reverse loop begins, run the
  inverse of that half-step:
  add_rc(state, 2*NS) + lbox_layer_inv + sbox_layer_inv.

No tweakey XOR is introduced around the peeled half-step (the per-step
tweakey injection lives at the end of the encrypt step and the start of
the decrypt step, both of which we skip for the half-step).
"""

import sys
import re

PATH = sys.argv[1]
src = open(PATH).read()

ENC_INSERT = """
  // Spook medium-variant peeled half-step (rho = 0 of step s = NS).
  sbox_layer(state);
  lbox_layer(state);
  add_rc(state, 2);

"""

DEC_INSERT = """  // Spook medium-variant peeled half-step inverse (undoes the encrypt
  // peeled round at index r = 2).
  add_rc(state, 2);
  lbox_layer_inv(state);
  sbox_layer_inv(state);

"""

# --- encrypt: insert just before the closing state2bytes(c, state); -------
enc_re = re.compile(
    r"(void\s+clyde128_encrypt\b.*?)(\n\s*state2bytes\(c, state\);\s*\n\})",
    re.DOTALL,
)
m = enc_re.search(src)
assert m, "clyde128_encrypt closing block not found"
src = (
    src[: m.start(2)]
    + "\n"
    + ENC_INSERT
    + "  state2bytes(c, state);\n}"
    + src[m.end() :]
)

# --- decrypt: insert just before the per-step reverse loop ----------------
dec_re = re.compile(
    r"(void\s+clyde128_decrypt\b.*?bytes2state\(state, c\);\s*\n)(\s*for \(int s =)",
    re.DOTALL,
)
m = dec_re.search(src)
assert m, "clyde128_decrypt reverse loop not found"
src = src[: m.end(1)] + DEC_INSERT + src[m.start(2) :]

open(PATH, "w").write(src)
