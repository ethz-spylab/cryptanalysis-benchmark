#!/usr/bin/env python3
"""Pin the Blender digest size n by editing the CLI default --hashbitlen.

Blender's one scaling knob is the digest/structural size ``n`` (= wordCount),
selected at ``Init`` in Blender.c via ``w = hashbitlen / {16,32,64}``. No
upstream ``#define`` fixes ``n``; it is the runtime digest length. The
HashCollisionGame oracle calls ``cli hash`` WITHOUT a ``--hashbitlen`` flag, so
the digest size is governed entirely by the CLI default in ``cli.c``
(``args.hashbitlen = 256;`` plus the help string ``(default: 256)``).

This patcher rewrites both occurrences to the requested value, so a weakened
build hashes at the pinned ``n`` for every oracle call. Operates on raw bytes;
fails loudly (non-zero exit) if either substitution is missing, so a botched
patch can never silently yield an unweakened variant.

Usage: patch_blender.py <path/to/cli.c> <hashbitlen>
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_blender.py <cli.c> <hashbitlen>\n")
        return 2

    path = sys.argv[1]
    value = int(sys.argv[2])

    # Init only accepts wordCount in [6, 10]; n must select a supported
    # word-size path. Guard the obviously-invalid range; the generator chooses
    # concrete values that land on valid Init paths.
    if value <= 0 or value % 8 != 0:
        sys.stderr.write(
            f"FATAL: hashbitlen={value} must be a positive multiple of 8\n"
        )
        return 2

    with open(path, "rb") as f:
        data = f.read()

    # 1) the runtime default:  args.hashbitlen = <num>;   (dot, not the -> form)
    pat_default = re.compile(rb"(args\.hashbitlen\s*=\s*)\d+(\s*;)")
    data, n1 = pat_default.subn(rb"\g<1>%d\g<2>" % value, data)

    # 2) the hashbitlen help string:  ...in bits (default: <num>)
    #    Anchored to "bits (default:" so the unrelated --count help line
    #    "(default: 1)" is left untouched.
    pat_help = re.compile(rb"(in bits \(default:\s*)\d+(\))")
    data, n2 = pat_help.subn(rb"\g<1>%d\g<2>" % value, data)

    if n1 == 0:
        sys.stderr.write(
            f"FATAL: 'args.hashbitlen = <num>;' default not found in {path}\n"
        )
        return 1
    if n2 == 0:
        sys.stderr.write(f"FATAL: help-string '(default: <num>)' not found in {path}\n")
        return 1

    with open(path, "wb") as f:
        f.write(data)

    sys.stderr.write(
        f"patched hashbitlen default -> {value} "
        f"({n1} assignment, {n2} help-string occurrence(s)) in {path}\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
