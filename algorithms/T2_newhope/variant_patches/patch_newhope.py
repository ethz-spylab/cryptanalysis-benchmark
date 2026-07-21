#!/usr/bin/env python3
"""Apply NewHope's CBD-parameter (k / eta) weakening to an extracted source tree.

Mechanism-migration patcher for T2_newhope (see ../generate_variants.sh). It
reproduces — byte-for-byte — the edits the previous build-time injection applied
via `sed`, but now against the freshly-extracted upstream tree so the result can
be repacked into the same archive build_cli.sh expects.

Usage:  patch_newhope.py <newhope/ref dir> <eta>

Reduces NewHope's centered-binomial noise parameter k from 8 to <eta>:
  1. params.h:  `#define NEWHOPE_K 8` -> `#define NEWHOPE_K <eta>`
  2. poly.c:    delete the `#if NEWHOPE_K != 8 / #error / #endif` guard block
                (the hand-unrolled cbd works for any k <= 8 once inputs are masked)
  3. poly.c:    mask the two cbd byte reads to the low k bits so hw(a),hw(b) in
                [0,k] -- i.e. the centered-binomial parameter is genuinely k.

Upstream sources are CRLF; CR is stripped before the line-anchored edits, exactly
as the original injection did (`sed -i 's/\\r$//' params.h poly.c`). The script
fails loudly if any edit matched zero occurrences, so a silently-unweakened
variant can never be produced.
"""
import os
import re
import sys


def strip_cr(data: bytes) -> bytes:
    # Equivalent to `sed -i 's/\r$//'` on a CRLF file: drop the CR before each LF.
    return data.replace(b"\r\n", b"\n")


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_newhope.py <newhope/ref dir> <eta>\n")
        return 2
    src_dir = sys.argv[1]
    eta = sys.argv[2]
    if not re.fullmatch(r"[0-9]+", eta):
        sys.stderr.write("error: eta must be an integer\n")
        return 2

    params_path = os.path.join(src_dir, "params.h")
    poly_path = os.path.join(src_dir, "poly.c")

    # --- params.h: strip CR, reduce NEWHOPE_K -------------------------------
    params = strip_cr(open(params_path, "rb").read())
    params, n = re.subn(
        rb"(?m)^#define NEWHOPE_K 8",
        b"#define NEWHOPE_K " + eta.encode(),
        params,
    )
    if n < 1:
        sys.stderr.write("error: no `#define NEWHOPE_K 8` in params.h\n")
        return 1
    open(params_path, "wb").write(params)

    # --- poly.c: strip CR, delete guard, mask cbd reads ---------------------
    poly = strip_cr(open(poly_path, "rb").read())

    # Delete the `#if NEWHOPE_K != 8` .. `#endif` guard block (inclusive),
    # mirroring `sed '/^#if NEWHOPE_K != 8$/,/^#endif$/d'`.
    lines = poly.split(b"\n")
    out = []
    deleting = False
    deleted = 0
    for line in lines:
        if not deleting and line == b"#if NEWHOPE_K != 8":
            deleting = True
            deleted += 1
            continue
        if deleting:
            deleted += 1
            if line == b"#endif":
                deleting = False
            continue
        out.append(line)
    if deleted < 1 or deleting:
        sys.stderr.write("error: `#if NEWHOPE_K != 8` guard not found/closed in poly.c\n")
        return 1
    poly = b"\n".join(out)

    poly, na = re.subn(
        rb"a = buf\[2\*j\];",
        rb"a = buf[2*j] & ((1<<NEWHOPE_K)-1);",
        poly,
    )
    poly, nb = re.subn(
        rb"b = buf\[2\*j\+1\];",
        rb"b = buf[2*j+1] & ((1<<NEWHOPE_K)-1);",
        poly,
    )
    if na < 1 or nb < 1:
        sys.stderr.write("error: cbd byte reads not found in poly.c\n")
        return 1
    open(poly_path, "wb").write(poly)

    return 0


if __name__ == "__main__":
    sys.exit(main())
