#!/usr/bin/env python3
"""Patch the MD6 round count r in md6_mode.c (md6_default_r body).

Replaces the line `r = 40 + (d/4);` inside md6_default_r with a fixed small
constant `r = <value>;`, reducing the number of compression rounds (the single
parameter that governs the strength of the MD6 feedback recurrence).

Usage: patch_md6.py <path/to/md6_mode.c> <value>

Operates on raw bytes so the file's CRLF line endings are preserved. Fails
loudly (non-zero exit) if no substitution was made, so a botched patch can never
silently yield an unweakened variant.
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_md6.py <md6_mode.c> <r-value>\n")
        return 2

    path = sys.argv[1]
    value = int(sys.argv[2])
    if not (0 <= value <= 255):
        sys.stderr.write(f"FATAL: r={value} outside valid range [0, md6_max_r=255]\n")
        return 2

    with open(path, "rb") as f:
        data = f.read()

    # Match `r = 40 + (d/4);` with flexible whitespace, in the bytes.
    pattern = re.compile(rb"r\s*=\s*40\s*\+\s*\(\s*d\s*/\s*4\s*\)\s*;")
    replacement = b"r = %d;" % value

    new_data, n = pattern.subn(replacement, data)
    if n == 0:
        sys.stderr.write(
            f"FATAL: pattern 'r = 40 + (d/4);' not found in {path}; nothing patched\n"
        )
        return 1

    with open(path, "wb") as f:
        f.write(new_data)

    sys.stderr.write(f"patched {n} occurrence(s): r -> {value} in {path}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
