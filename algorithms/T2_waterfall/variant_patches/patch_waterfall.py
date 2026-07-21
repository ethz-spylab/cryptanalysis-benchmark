#!/usr/bin/env python3
"""Reduce the Xbox() round count in Waterfall's reference implementation.

Usage:  patch_waterfall.py <path/to/Waterfall.c> <xbox_rounds>

Xbox() (the sole source of non-linearity in Waterfall) unrolls an
S-box-feedback + 1-byte-rotate step 4 times by default.  This patcher rewrites
that unrolled body to keep only the first <xbox_rounds> iterations, uniformly
weakening diffusion across every absorption and finalization step.

The upstream file uses CRLF line endings, so we operate in binary mode and
preserve them exactly.  The script fails loudly (non-zero exit) if the expected
unrolled block is not found or if nothing changed -- so a botched edit aborts
generation rather than silently shipping an un-weakened variant.
"""
import sys

# Line fragments, expressed with '\n' then converted to CRLF to match upstream.
HEADER = ('static void Xbox ( unsigned int *pword ) {\n\n'
          '#if DEBUG>2\n\tprintf("  X-box steps: %8.8x ", *pword);\n#endif\n')
PAIR = ('\t*pword ^= xbox[*pword & 0xFF];\n'
        '\t*pword = (*pword<<24) | (*pword>>8);\n')
MID = '#if DEBUG>2\n\tprintf("%8.8x ", *pword);\n#endif\n'
FINAL = '#if DEBUG>2\n\tprintf("%8.8x\\n", *pword);\n#endif\n'
FOOTER = '}'


def crlf(s: str) -> bytes:
    return s.replace('\n', '\r\n').encode()


def build_body(rounds: int) -> str:
    s = HEADER
    for i in range(rounds):
        s += PAIR
        s += MID if i < rounds - 1 else FINAL
    s += FOOTER
    return s


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    path, rounds = sys.argv[1], int(sys.argv[2])
    if not (1 <= rounds <= 4):
        sys.stderr.write("xbox_rounds must be in 1..4\n")
        return 2

    orig = crlf(build_body(4))   # the pristine 4-iteration Xbox body
    new = crlf(build_body(rounds))

    with open(path, 'rb') as fh:
        data = fh.read()
    if orig not in data:
        sys.stderr.write("ERROR: pristine Xbox() block not found in %s\n" % path)
        return 1
    patched = data.replace(orig, new, 1)
    if patched == data:
        sys.stderr.write("ERROR: patch made no change to %s\n" % path)
        return 1
    with open(path, 'wb') as fh:
        fh.write(patched)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
