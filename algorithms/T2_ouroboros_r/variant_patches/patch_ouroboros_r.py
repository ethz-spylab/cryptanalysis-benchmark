#!/usr/bin/env python3
"""Set a `#define <MACRO> <int>` to a new value in a header file.

Usage:
    patch_ouroboros_r.py <header_file> <macro_name> <new_value>

Used by generate_variants.sh to scale Ouroboros-R's extension degree m, which
lives in TWO synchronized macros:
  - PARAM_M  in src/parameters.h
  - FIELD_M  in src/ffi/ffi.h

Fails loudly (non-zero exit) if it does not change exactly one definition, so a
mis-applied patch aborts generation rather than silently shipping an unweakened
variant.
"""

import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write(
            "usage: patch_ouroboros_r.py <header_file> <macro_name> <new_value>\n"
        )
        return 2

    path, macro, value = sys.argv[1], sys.argv[2], sys.argv[3]
    int(value)  # validate numeric

    with open(path, "r") as f:
        text = f.read()

    # Match: #define <MACRO> <digits>   (preserve trailing comment / whitespace)
    pattern = re.compile(
        r"(^[ \t]*#[ \t]*define[ \t]+" + re.escape(macro) + r"[ \t]+)\d+",
        re.MULTILINE,
    )
    new_text, n = pattern.subn(r"\g<1>" + value, text)

    if n != 1:
        sys.stderr.write(
            f"ERROR: expected exactly 1 definition of {macro} in {path}, found {n}\n"
        )
        return 1

    with open(path, "w") as f:
        f.write(new_text)

    print(f"patched {macro} -> {value} in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
