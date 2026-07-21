#!/usr/bin/env python3
"""Generation-time weakening patcher for T2_sparkle (Schwaemm256-128).

Sets SPARKLE_STEPS_SLIM to the requested band value in schwaemm_cfg.h.

This reproduces EXACTLY the edit the old build-time injection performed:
  1. tr -d '\r'  (normalise CRLF -> LF for the whole file)
  2. sed 's/^#define SPARKLE_STEPS_SLIM  7$/#define SPARKLE_STEPS_SLIM  <VAL>/'

The literal `#define SPARKLE_STEPS_SLIM  7` appears in three #ifdef branches
(SCHWAEMM128_128 / SCHWAEMM256_128 / SCHWAEMM192_192); only SCHWAEMM256_128 is
compiled, but replacing all three is harmless. The SCHWAEMM256_256 branch uses
`SPARKLE_STEPS_SLIM  8` and is intentionally left untouched.

Usage:  patch_sparkle.py <path/to/schwaemm_cfg.h> <new_steps_slim_value>
Fails loudly (exit 1) if it does not change at least one occurrence.
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(
            "usage: patch_sparkle.py <schwaemm_cfg.h> <steps_slim_value>\n"
        )
        return 2

    path, value = sys.argv[1], sys.argv[2]

    with open(path, "rb") as fh:
        data = fh.read()

    # Step 1: strip all CR (equivalent to `tr -d '\r'`).
    text = data.replace(b"\r", b"")

    # Step 2: replace the slim-step count (`  7` -> `  <value>`), line-anchored.
    pattern = re.compile(rb"^#define SPARKLE_STEPS_SLIM  7$", re.MULTILINE)
    replacement = b"#define SPARKLE_STEPS_SLIM  " + value.encode()
    new_text, n = pattern.subn(replacement, text)

    if n == 0:
        sys.stderr.write(
            f"ERROR: no `#define SPARKLE_STEPS_SLIM  7` line found in {path}; "
            "refusing to ship an unweakened variant\n"
        )
        return 1

    with open(path, "wb") as fh:
        fh.write(new_text)

    sys.stderr.write(
        f"patched {path}: SPARKLE_STEPS_SLIM -> {value} ({n} occurrence(s))\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
