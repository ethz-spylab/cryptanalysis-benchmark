#!/usr/bin/env python3
"""KINDI Option-B weakening patcher (generation-time, never shipped in the image).

Reduces the effective Module-LWE dimension n_eff = KINDI_KEM_N * KINDI_KEM_L by
lowering the ring degree KINDI_KEM_N to a smaller power of two (the proposal's
Hard N=128 / Easy N=64 bands, L kept at 3).  KINDI's FO transform embeds a fixed
256-bit security seed s1 (KINDI_KEM_S1SIZE = 256/8) into 256 coefficients of a
degree-N polynomial, so N>=256 is otherwise hard-wired (core.c recover_s1() and
gen_randomness() both index s1 bits over [0, 8*S1SIZE)).  We therefore also shrink
the embedded seed to N bits (KINDI_KEM_S1SIZE = N/8): this deliberately lowers the
effective seed entropy (exactly what a weakened instance should do) and makes the
seed embedding read exactly N coefficients -> in bounds -> end-to-end consistent.
The shared-secret / public-seed sizes (HASHSIZE = SEEDSIZE = 2*lambda/8 = 32) are
unchanged, so the KEM keygen/encaps/decaps still agree on a 32-byte shared secret.

The complex-FFT twiddle tables ship only for N in {256, 512}; this script generates
the validated data_fft/<N>/{psis,inverse_psi_n,omegas,inverse_omegas}_{real,img}.data
tables plus bitrev<N>.code for the requested N, and adds the matching
"#if/#elif KINDI_KEM_N == <N>" include branches to poly.h and fft_transform.c.  The
generators were validated to reproduce the shipped 256 and 512 tables to within
floating-point error before use.

Usage:
    patch_kindi.py <EXTRACT_ROOT> <N>

<EXTRACT_ROOT> is the directory the KINDI archive was unzipped into (contains
KINDI/Reference_Implementation/...).  <N> is the new ring degree (128 or 64).
Fails loudly (non-zero exit) if any expected edit changes 0 occurrences.
"""

import math
import os
import sys


def fmt(x):
    # Full round-trip double precision; valid C double literal.
    return repr(float(x))


def write_data(path, values):
    lines = []
    n = len(values)
    for i, v in enumerate(values):
        sep = " ," if i < n - 1 else ""
        lines.append(fmt(v) + sep)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def gen_omegas(N, sign):
    real = [1.0] * N
    img = [0.0] * N
    m = 2
    while m <= N:
        half = m // 2
        for i in range(half):
            ang = sign * 2.0 * math.pi * i / m
            real[half + i] = math.cos(ang)
            img[half + i] = math.sin(ang)
        m *= 2
    return real, img


def gen_tables(datadir, N):
    nd = os.path.join(datadir, str(N))
    os.makedirs(nd, exist_ok=True)
    # psi = e^{i*pi*i/N} (primitive 2N-th root), forward psi-loop
    psis_real = [math.cos(math.pi * i / N) for i in range(N)]
    psis_img = [math.sin(math.pi * i / N) for i in range(N)]
    # inverse psi-loop folded with 1/N scaling: (1/N) * psi^{-i}
    inv_psi_n_real = [math.cos(math.pi * i / N) / N for i in range(N)]
    inv_psi_n_img = [-math.sin(math.pi * i / N) / N for i in range(N)]
    om_real, om_img = gen_omegas(N, +1)
    iom_real, iom_img = gen_omegas(N, -1)
    write_data(os.path.join(nd, "psis_real.data"), psis_real)
    write_data(os.path.join(nd, "psis_img.data"), psis_img)
    write_data(os.path.join(nd, "inverse_psi_n_real.data"), inv_psi_n_real)
    write_data(os.path.join(nd, "inverse_psi_n_img.data"), inv_psi_n_img)
    write_data(os.path.join(nd, "omegas_real.data"), om_real)
    write_data(os.path.join(nd, "omegas_img.data"), om_img)
    write_data(os.path.join(nd, "inverse_omegas_real.data"), iom_real)
    write_data(os.path.join(nd, "inverse_omegas_img.data"), iom_img)
    # bitrev<N>.code: swap statements for the bit-reversal permutation
    bits = N.bit_length() - 1
    swaps = []
    for i in range(N):
        r = int("{:0{}b}".format(i, bits)[::-1], 2)
        if i < r:
            swaps.append((i, r))
    lines = []
    for a, b in swaps:
        lines.append("t = r[%d];" % a)
        lines.append("r[%d] = r[%d];" % (a, b))
        lines.append("r[%d] = t;" % b)
    with open(os.path.join(datadir, "bitrev%d.code" % N), "w") as f:
        f.write("\n".join(lines) + "\n")


def replace_once(text, old, new, label):
    cnt = text.count(old)
    if cnt != 1:
        sys.stderr.write(
            "patch_kindi: expected exactly 1 occurrence of %s, found %d\n"
            % (label, cnt)
        )
        sys.exit(1)
    return text.replace(old, new, 1)


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_kindi.py <EXTRACT_ROOT> <N>\n")
        sys.exit(2)
    root = sys.argv[1]
    N = int(sys.argv[2])
    paramdir = os.path.join(
        root, "KINDI", "Reference_Implementation", "kem", "KINDI-256-3-4-2"
    )
    if not os.path.isdir(paramdir):
        sys.stderr.write("patch_kindi: param dir not found: %s\n" % paramdir)
        sys.exit(1)

    # 1) params.h: ring degree N and embedded-seed length S1SIZE = N/8.
    ph = os.path.join(paramdir, "params.h")
    t = open(ph).read()
    t = replace_once(
        t, "#define KINDI_KEM_N 256", "#define KINDI_KEM_N %d" % N, "KINDI_KEM_N define"
    )
    t = replace_once(
        t,
        "#define KINDI_KEM_S1SIZE (256/8)",
        "#define KINDI_KEM_S1SIZE (%d/8)" % N,
        "KINDI_KEM_S1SIZE define",
    )
    open(ph, "w").write(t)

    # 2) FFT twiddle tables + bitrev permutation for the new N.
    gen_tables(os.path.join(paramdir, "data_fft"), N)

    # 3) poly.h: add an "#elif KINDI_KEM_N == <N>" branch (before the 512 branch).
    plh = os.path.join(paramdir, "poly.h")
    t = open(plh).read()
    incs = []
    for name in (
        "psis_real",
        "psis_img",
        "inverse_psi_n_real",
        "inverse_psi_n_img",
        "omegas_real",
        "omegas_img",
        "inverse_omegas_real",
        "inverse_omegas_img",
    ):
        var = name
        if name == "psis_img":
            var = "psis_img"
        incs.append(
            'static const poly_f %s = {\n#include "data_fft/%d/%s.data"\n};'
            % (var, N, name)
        )
    # variable names in poly.h: psis_real, psis_img, inverse_psi_n_real,
    # inverse_psi_n_img, omegas_real, omegas_img, inverse_omegas_real,
    # inverse_omegas_img -- identical to the .data basenames above.
    branch = "#elif KINDI_KEM_N == %d\n%s\n#elif KINDI_KEM_N == 512" % (
        N,
        "\n".join(incs),
    )
    t = replace_once(t, "#elif KINDI_KEM_N == 512", branch, "poly.h 512 branch")
    open(plh, "w").write(t)

    # 4) fft_transform.c: add a bitrev include guard for the new N.
    ftc = os.path.join(paramdir, "fft_transform.c")
    t = open(ftc).read()
    new_guard = (
        '#if KINDI_KEM_N == %d\n#include "data_fft/bitrev%d.code"\n#endif\n'
        "#if KINDI_KEM_N == 512" % (N, N)
    )
    t = replace_once(
        t, "#if KINDI_KEM_N == 512", new_guard, "fft_transform.c 512 guard"
    )
    open(ftc, "w").write(t)


if __name__ == "__main__":
    main()
