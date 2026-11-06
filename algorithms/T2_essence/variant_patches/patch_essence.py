#!/usr/bin/env python3
"""Reduce the ESSENCE compression step count (security parameter).

Usage: patch_essence.py <path/to/essence_api.h> <num_steps>

Rewrites the single `#define ESSENCE_COMPRESS_NUM_STEPS <N>` line to the given
value. Fails loudly (non-zero exit) if it does not change exactly one line, so a
silent unweakened variant can never be produced.
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_essence.py <essence_api.h> <num_steps>\n")
        return 2
    path, value = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"\d+", value):
        sys.stderr.write(f"error: num_steps must be an integer, got {value!r}\n")
        return 2

    with open(path, "r") as f:
        src = f.read()

    # Match only the active macro definition, not the surrounding comments.
    pattern = re.compile(r"^(#define\s+ESSENCE_COMPRESS_NUM_STEPS\s+)\d+", re.MULTILINE)
    new_src, n = pattern.subn(r"\g<1>" + value, src)
    if n != 1:
        sys.stderr.write(
            f"error: expected exactly 1 substitution, made {n} in {path}\n"
        )
        return 1

    with open(path, "w") as f:
        f.write(new_src)
    sys.stderr.write(f"patched ESSENCE_COMPRESS_NUM_STEPS -> {value} in {path}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
