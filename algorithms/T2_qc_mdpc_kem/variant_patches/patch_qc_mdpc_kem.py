#!/usr/bin/env python3
"""Parameterized weakening patch for the QC-MDPC KEM reference implementation.

Edits the four controlling values in
    Reference_Implementation/kem/mdpc/internal.h
to a reduced (R, W, T) parameter set and rewrites the bit-flipping decoder's
`thresholds[]` schedule (which is hard-calibrated for the full-strength
WI = 137 and would otherwise never trigger a flip at the reduced row weight,
making every decapsulation fail).

Usage:
    patch_qc_mdpc_kem.py <internal.h> <R> <W> <T> <th0,th1,...,th7>

All substitutions are asserted: if any of the #defines or the thresholds array
is not found / not changed, the script exits non-zero so generation aborts
rather than silently shipping an unweakened (or undecodable) variant.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
"""
import re
import sys


def sub_once(pattern, repl, text, what):
    new, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        sys.exit("patch_qc_mdpc_kem: failed to substitute %s "
                 "(matched %d times)" % (what, n))
    return new


def main():
    if len(sys.argv) != 6:
        sys.exit("usage: patch_qc_mdpc_kem.py <internal.h> <R> <W> <T> "
                 "<th0,...,th7>")
    path, R, W, T, ths = sys.argv[1:]

    # sanity: R must be prime with 2 a primitive root, WI = W/2 must be odd.
    R, W, T = int(R), int(W), int(T)
    if W % 2 != 0:
        sys.exit("patch_qc_mdpc_kem: W must be even (WI = W/2 integral)")
    if (W // 2) % 2 == 0:
        sys.exit("patch_qc_mdpc_kem: WI = W/2 must be ODD or the second "
                 "circulant block is divisible by (x-1) and is non-invertible")
    th_list = [int(x) for x in ths.split(",")]
    th_str = ", ".join(str(x) for x in th_list)

    with open(path) as f:
        src = f.read()

    src = sub_once(r"#define MDPC_R\s+\d+", "#define MDPC_R %d" % R, src,
                   "MDPC_R")
    src = sub_once(r"#define MDPC_W\s+\d+", "#define MDPC_W %d" % W, src,
                   "MDPC_W")
    src = sub_once(r"#define MDPC_T\s+\d+", "#define MDPC_T %d" % T, src,
                   "MDPC_T")
    src = sub_once(
        r"static const unsigned int thresholds\[\]\s*=\s*\{[^}]*\};",
        "static const unsigned int thresholds[] = { %s };" % th_str,
        src, "thresholds[]")

    with open(path, "w") as f:
        f.write(src)

    print("patched %s -> R=%d W=%d T=%d WI=%d thresholds={%s}"
          % (path, R, W, T, W // 2, th_str))


if __name__ == "__main__":
    main()
