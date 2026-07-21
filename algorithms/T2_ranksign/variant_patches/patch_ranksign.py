#!/usr/bin/env python3
"""Scale-down patcher for RankSign variants.

Usage:
  patch_ranksign.py <SRC_DIR> <M> <N> <K> <T> <R> <R2> <COEFFS_CSV>

<SRC_DIR> must contain parameters.h and api.h, and ffi_elt.c either directly or
under ffi/. Edits, in place:
  * parameters.h : PARAM_M/N/K/T/R/R2 (PARAM_D=2, PARAM_T2=1 kept fixed).
  * ffi_elt.c    : generateExtension() -> installs the supplied degree-M
                   irreducible modulus over GF(2^32) (COEFFS_CSV = M+1 ints,
                   low degree first, each an mpfq_2_32 element as a 32-bit int).
  * api.h        : CRYPTO_{PUBLICKEY,SECRETKEY,}BYTES recomputed from the params.
Fails loudly (nonzero exit) if any edit changes 0 occurrences.
"""
import os, re, sys

def die(msg):
    sys.stderr.write("patch_ranksign: %s\n" % msg); sys.exit(1)

def find(src, *cands):
    for c in cands:
        p = os.path.join(src, c)
        if os.path.isfile(p): return p
    die("could not find any of %s under %s" % (cands, src))

def sub1(text, pat, repl, what):
    new, n = re.subn(pat, repl, text)
    if n < 1: die("no substitution for %s" % what)
    return new

def main():
    if len(sys.argv) != 9: die("expected 8 args, got %d" % (len(sys.argv)-1))
    src = sys.argv[1]
    M, N, K, T, R, R2 = (int(x) for x in sys.argv[2:8])
    coeffs = [int(x) for x in sys.argv[8].split(",")]
    if len(coeffs) != M + 1: die("expected %d coeffs, got %d" % (M+1, len(coeffs)))
    if coeffs[-1] != 1: die("leading (degree-M) coeff must be 1 (monic)")

    D, T2 = 2, 1  # fixed by the reference implementation (d=2 hardwired in sign())
    FFI_BASEELT_BYTES = 4                      # GF(2^32)
    FFI_ELT_BYTES = M * FFI_BASEELT_BYTES
    PUBLICKEY = (T + K) * (N - K) * FFI_ELT_BYTES
    F_B   = D * FFI_ELT_BYTES
    DH_B  = N * N * FFI_BASEELT_BYTES
    INVP_B= (N + T) * (N + T) * FFI_BASEELT_BYTES
    INVA_B= (N - K) * (N - K) * FFI_ELT_BYTES
    R_B   = (N - K) * T * FFI_ELT_BYTES
    SECRETKEY = F_B + DH_B + INVP_B + INVA_B + R_B + PUBLICKEY
    SIGNATURE = R * FFI_ELT_BYTES + (N + T) * R * FFI_BASEELT_BYTES + 1

    # --- parameters.h ---
    ph = find(src, "parameters.h")
    t = open(ph).read()
    for name, val in (("PARAM_M", M), ("PARAM_N", N), ("PARAM_K", K),
                      ("PARAM_T", T), ("PARAM_R", R), ("PARAM_R2", R2)):
        t = sub1(t, r"(#define\s+%s\s+)\d+" % name, r"\g<1>%d" % val, name)
    open(ph, "w").write(t)

    # --- ffi_elt.c : replace generateExtension() ---
    fe = find(src, os.path.join("ffi", "ffi_elt.c"), "ffi_elt.c")
    t = open(fe).read()
    body = []
    body.append("void generateExtension(MPFQ_FIELD field) {")
    body.append("\tif(!extensionGenerated) {")
    body.append("\t\tffi_baseElt coeff;")
    body.append("\t\tMPFQ_TAG(init)(field, coeff);")
    body.append("\t\tMPFQ_TAG(poly_init)(field, IRR, PARAM_M);")
    body.append("\t\tstatic const unsigned long IRR_COEFFS[PARAM_M + 1] = {%s};"
                % ", ".join("%dUL" % c for c in coeffs))
    body.append("\t\tint index;")
    body.append("\t\tfor(index=0 ; index<=PARAM_M ; index++) {")
    body.append("\t\t\t*coeff = IRR_COEFFS[index];")
    body.append("\t\t\tMPFQ_TAG(poly_setcoef)(field, IRR, coeff, index);")
    body.append("\t\t}")
    body.append("\t\tMPFQ_TAG(clear)(field, coeff);")
    body.append("\t\textensionGenerated = 1;")
    body.append("\t}")
    body.append("}")
    newfunc = "\n".join(body) + "\n"
    t2 = re.sub(r"void generateExtension\(MPFQ_FIELD field\) \{.*?\n\}\n",
                newfunc, t, count=1, flags=re.DOTALL)
    if t2 == t: die("generateExtension not replaced")
    open(fe, "w").write(t2)

    # --- api.h : recompute byte sizes ---
    ah = find(src, "api.h")
    t = open(ah).read()
    t = sub1(t, r"(#define\s+CRYPTO_SECRETKEYBYTES\s+)\d+", r"\g<1>%d" % SECRETKEY, "SECRETKEYBYTES")
    t = sub1(t, r"(#define\s+CRYPTO_PUBLICKEYBYTES\s+)\d+", r"\g<1>%d" % PUBLICKEY, "PUBLICKEYBYTES")
    t = sub1(t, r"(#define\s+CRYPTO_BYTES\s+)\d+", r"\g<1>%d" % SIGNATURE, "CRYPTO_BYTES")
    open(ah, "w").write(t)

    sys.stderr.write("patch_ranksign OK: M=%d N=%d K=%d T=%d R=%d R2=%d "
                     "pk=%d sk=%d sig=%d\n" % (M,N,K,T,R,R2,PUBLICKEY,SECRETKEY,SIGNATURE))

if __name__ == "__main__":
    main()
