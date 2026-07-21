#!/usr/bin/env python3
"""Scale-down patcher for CLX (NIST LWC round 1).

Rewrites the per-block / framing permutation step counts NROUND1 and NROUND2
in the clx128 reference encrypt.c. This reproduces, at generation time, the
exact edit the old build-time sed injection performed (defaults 384, 1152).

Usage: patch_clx.py <path/to/encrypt.c> <NROUND1> <NROUND2>

Fails loudly (non-zero exit) if either #define is not found / not changed.
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write(
            "usage: patch_clx.py <encrypt.c> <NROUND1> <NROUND2>\n"
        )
        return 2

    path, n1, n2 = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(path, "r") as f:
        src = f.read()

    # Same anchors as the original sed expressions:
    #   ^[[:space:]]*#define[[:space:]]+NROUND1[[:space:]]+384.*  -> #define NROUND1 <n1>
    #   ^[[:space:]]*#define[[:space:]]+NROUND2[[:space:]]+1152.* -> #define NROUND2 <n2>
    src, c1 = re.subn(
        r"^[ \t]*#define[ \t]+NROUND1[ \t]+384.*$",
        "#define NROUND1 %s" % n1,
        src,
        flags=re.MULTILINE,
    )
    src, c2 = re.subn(
        r"^[ \t]*#define[ \t]+NROUND2[ \t]+1152.*$",
        "#define NROUND2 %s" % n2,
        src,
        flags=re.MULTILINE,
    )

    if c1 < 1:
        sys.stderr.write("ERROR: NROUND1 384 not found in %s\n" % path)
        return 1
    if c2 < 1:
        sys.stderr.write("ERROR: NROUND2 1152 not found in %s\n" % path)
        return 1

    with open(path, "w") as f:
        f.write(src)

    return 0


if __name__ == "__main__":
    sys.exit(main())
