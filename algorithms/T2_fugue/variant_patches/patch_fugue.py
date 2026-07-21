#!/usr/bin/env python3
"""Generation-time patcher for the Fugue-256 final-SMIX (G2) round count.

Reduces the number of final SMIX (G2) iterations `t` in the 256-bit config
row of the upstream reference `fugue.c`. The 256-bit row is declared as
`{256,{8 ,30,2,5,13},{0}}` where the fields are `{n, s, k, r, t}`; `t` is
the final-SMIX iteration count (upstream default 13). The default CLI
hashbitlen is 256, so only this row matters.

Usage:
    patch_fugue.py <path/to/fugue.c> <new_t>

Fails loudly (non-zero exit) if it does not change exactly one occurrence,
so a failed weakening aborts variant generation rather than silently
shipping a full-strength variant.
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_fugue.py <fugue.c> <new_t>\n")
        return 2

    target = sys.argv[1]
    new_t = sys.argv[2]

    if not re.fullmatch(r"\d+", new_t):
        sys.stderr.write(f"error: new_t must be a non-negative integer, got {new_t!r}\n")
        return 2

    with open(target, "r", encoding="utf-8") as fh:
        src = fh.read()

    # Match the 256-bit config row, capturing everything up to (and including)
    # the comma before the final `t` field, and the trailing `}`.
    pattern = re.compile(r"(\{256,\{8 ,30,2,5,)13(\})")
    new_src, n = pattern.subn(rf"\g<1>{new_t}\g<2>", src)

    if n != 1:
        sys.stderr.write(
            f"error: expected exactly 1 substitution in {target}, made {n}\n"
        )
        return 1

    with open(target, "w", encoding="utf-8") as fh:
        fh.write(new_src)

    sys.stderr.write(f"patched {target}: Fugue-256 final-SMIX t 13 -> {new_t}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
