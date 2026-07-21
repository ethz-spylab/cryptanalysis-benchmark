#!/usr/bin/env python3
"""Scale-down patcher for Lepton (Light-I) variants.

Usage:
  patch_lepton.py <REF_SRC_DIR> <K>

<REF_SRC_DIR> must contain params.h (the Lepton reference params file). Edits, in
place, the Light-I noise/secret Hamming weight PARAM_K (the sole scaling knob):

  params.h : `#define PARAM_K 16` (inside the LIGHT_I block; 16 is unique to it)
             -> `#define PARAM_K <K>`

Everything else (N, M, RCN, BCH, sizes) derives from PARAM_K via existing macros
(CPA_SK_BYTES = 2*PARAM_K, PARAM_3K = 3*PARAM_K, poly_noise = uint16_t[PARAM_K]),
so no other edit is needed. Lowering PARAM_K reduces the Ring-LPN secret/error
weight -> the syndrome-decoding (DOOM-Prange) target weight drops from 2*16=32 to
2*K, making the ISD break reliably in-budget. Fails loudly if 0 occurrences change.
"""
import os
import re
import sys


def die(msg):
    sys.stderr.write("patch_lepton: %s\n" % msg)
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        die("expected 2 args (REF_SRC_DIR K), got %d" % (len(sys.argv) - 1))
    src = sys.argv[1]
    K = int(sys.argv[2])
    if not (1 <= K <= 15):
        die("K must be in 1..15 (strictly weaker than full Light-I K=16); got %d" % K)

    params = os.path.join(src, "params.h")
    if not os.path.isfile(params):
        die("could not find params.h under %s" % src)

    # params.h contains non-UTF-8 bytes in some comments (e.g. the "Paranoid"
    # headers), so read/write as latin-1 to preserve every byte 1:1.
    text = open(params, encoding="latin-1").read()
    # The literal `PARAM_K 16` occurs only in the LIGHT_I block (LIGHT_II uses 20,
    # MODER_* use 19/24/28/37, PARAN_* use 35/40). PARAM_3K uses `3*PARAM_K`.
    new, n = re.subn(r"(#define\s+PARAM_K\s+)16\b", r"\g<1>%d" % K, text)
    if n < 1:
        die("no substitution for PARAM_K (expected `#define PARAM_K 16` in LIGHT_I block)")
    if n > 1:
        die("expected exactly 1 PARAM_K substitution, got %d" % n)
    open(params, "w", encoding="latin-1").write(new)
    print("patch_lepton: PARAM_K 16 -> %d (%d sub)" % (K, n))


if __name__ == "__main__":
    main()
