#!/usr/bin/env python3
"""Rewrite HiMQ-3's api.h for a scaled-down (V, O1, O2, O3) parameter set.

HiMQ-3's api.h hand-codes many derived constants as arithmetic literals rather
than as formulas, so changing the layer/vinegar counts requires recomputing all
the dependents consistently (see algorithm_scaling_down/nist_pqc/himq_3.txt).
This patcher derives every dependent macro from the four primary knobs and
regenerates the whole api.h, then asserts the file actually changed.

Usage:
    patch_himq_3.py <path/to/api.h> <V> <O1> <O2> <O3>

The field q is left at P=256 (hardwired in gf256.c) and CRYPTO_ALGNAME is kept.
"""
import sys


def derive(V, O1, O2, O3):
    N = V + O1 + O2 + O3          # total variables n = V + O1 + O2 + O3
    M = O1 + O2 + O3              # equations m = O1 + O2 + O3
    V1 = V + O1
    V2 = V1 + O2
    # Secret central-map block layout (cumulative offsets), matching sign.c:
    #   delta : O1+O2          alpha : V*O1     beta : V*O2
    #   gamma : V1*O3          gamma': V2*O3    epsilon : epswid * O3
    alp = O1 + O2
    bet = alp + V * O1
    gam = bet + V * O2
    gam1 = gam + V1 * O3
    eps = gam1 + V2 * O3
    epswid = O1 * (O1 - 1) // 2
    sksize = eps + epswid * O3
    PKSIZE = N * N * M
    PKWID = N * N
    SKSIZE = N * N * M + M * M + N * N
    return dict(P=256, V=V, O1=O1, O2=O2, O3=O3, N=N, M=M, V1=V1, V2=V2,
                MM=M * M, NN=N * N, PKSIZE=PKSIZE, PKWID=PKWID, SKSIZE=SKSIZE,
                alp=alp, bet=bet, gam=gam, gam1=gam1, eps=eps,
                epswid=epswid, sksize=sksize)


def render(c):
    return f"""//
//  api.h
//
//  in the project HiMQ-3 submitted by Shim, Kyung-Ah, Park, Cheol-Min, and Kim, Aeyoung on 9/29/17
//
//  Parameters scaled down for the CryptanalysisBench variant generator.
//

#define P {c['P']}
#define V {c['V']}
#define O1 {c['O1']}
#define O2 {c['O2']}
#define O3 {c['O3']}
#define N {c['N']}
#define M {c['M']}
#define V1 {c['V1']}
#define V2 {c['V2']}
#define L_MSG M
#define L_SIGN N
#define MM {c['MM']}
#define NN {c['NN']}

#define CRYPTO_SECRETKEYBYTES {c['SKSIZE']}
#define CRYPTO_PUBLICKEYBYTES {c['PKSIZE']}
#define CRYPTO_BYTES N
#define CRYPTO_RANDOMBYTES M
#define CRYPTO_ALGNAME "HiMQ3"

#define PKSIZE {c['PKSIZE']}
#define PKWID {c['PKWID']}
#define SKSIZE {c['SKSIZE']}


#define alp ({c['alp']})
#define bet {c['bet']}
#define gam {c['gam']}
#define gam1 {c['gam1']}
#define eps {c['eps']}
#define sksize {c['sksize']}
#define epswid {c['epswid']}
"""


def main():
    if len(sys.argv) != 6:
        sys.exit("usage: patch_himq_3.py <api.h> <V> <O1> <O2> <O3>")
    path = sys.argv[1]
    V, O1, O2, O3 = (int(x) for x in sys.argv[2:6])
    with open(path, "r") as f:
        old = f.read()
    new = render(derive(V, O1, O2, O3))
    if new == old:
        sys.exit(f"ERROR: regenerated api.h identical to original ({path}); "
                 "patch had no effect")
    with open(path, "w") as f:
        f.write(new)
    print(f"patched {path}: V={V} O1={O1} O2={O2} O3={O3} "
          f"N={V+O1+O2+O3} M={O1+O2+O3}")


if __name__ == "__main__":
    main()
