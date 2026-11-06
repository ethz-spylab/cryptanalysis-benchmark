#!/usr/bin/env python3
"""Patch MeshHash's structural parameter `number_of_pipes`.

MeshHash has no separate round-count constant: the single structural knob
`number_of_pipes` governs both the internal-state width (64 bits per pipe) and
the per-block diffusion depth (one `normal_round` per pipe). It is fixed at run
time by `ComputeNumberOfPipes()` in meshhash.c under the clamps
`MIN_NUMBER_OF_PIPES` / `NUMBER_OF_EXTRA_PIPES` and the header constraint
`COUNTER_LENGTH <= MIN_NUMBER_OF_PIPES`.

This patcher forces a fixed pipe count by:
  * meshhash.c: replacing the body's `return number_of_pipes;` with
    `return <pipes>;` (overrides the hashbitlen-derived value + clamps).
  * meshhash.h: lowering `#define MIN_NUMBER_OF_PIPES` to <pipes> so the clamp
    cannot raise it back, and `#define COUNTER_LENGTH` to <pipes> to keep the
    header's `COUNTER_LENGTH <= MIN_NUMBER_OF_PIPES` invariant.

The squeeze emits `hashbitlen/8` bytes independently of the pipe count, so the
digest length is unchanged (default 256 bits) and the variants stay drop-in
comparable to the original.

Usage: patch_meshhash.py <path/to/Reference_Implementation> <pipes>

Fails loudly (non-zero exit) if any expected substitution makes zero changes,
so a botched patch can never silently yield an unweakened variant.
"""

import os
import re
import sys


def patch_file(path, pattern, replacement, label):
    with open(path, "rb") as f:
        data = f.read()
    new_data, n = pattern.subn(replacement, data)
    if n == 0:
        sys.stderr.write(
            f"FATAL: pattern for {label} not found in {path}; nothing patched\n"
        )
        sys.exit(1)
    with open(path, "wb") as f:
        f.write(new_data)
    return n


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(
            "usage: patch_meshhash.py <Reference_Implementation dir> <pipes>\n"
        )
        return 2

    ref_dir = sys.argv[1]
    pipes = int(sys.argv[2])
    # MeshHash requires at least 1 pipe (the state is calloc(pipes+1, ...)) and
    # at most MAX_NUMBER_OF_PIPES (256). The scaling bands use 2/3/4.
    if not (1 <= pipes <= 256):
        sys.stderr.write(f"FATAL: pipes={pipes} outside valid range [1, 256]\n")
        return 2

    c_path = os.path.join(ref_dir, "meshhash.c")
    h_path = os.path.join(ref_dir, "meshhash.h")
    for p in (c_path, h_path):
        if not os.path.isfile(p):
            sys.stderr.write(f"FATAL: expected source file missing: {p}\n")
            return 1

    # meshhash.c: force a fixed return in ComputeNumberOfPipes.
    patch_file(
        c_path,
        re.compile(rb"return\s+number_of_pipes\s*;"),
        b"return %d;" % pipes,
        "ComputeNumberOfPipes return",
    )

    # meshhash.h: lower MIN_NUMBER_OF_PIPES and COUNTER_LENGTH to <pipes>.
    patch_file(
        h_path,
        re.compile(rb"#define\s+MIN_NUMBER_OF_PIPES\s+\d+"),
        b"#define MIN_NUMBER_OF_PIPES %d" % pipes,
        "MIN_NUMBER_OF_PIPES define",
    )
    patch_file(
        h_path,
        re.compile(rb"#define\s+COUNTER_LENGTH\s+\d+"),
        b"#define COUNTER_LENGTH %d" % pipes,
        "COUNTER_LENGTH define",
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
