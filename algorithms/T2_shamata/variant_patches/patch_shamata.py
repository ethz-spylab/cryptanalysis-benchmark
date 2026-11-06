#!/usr/bin/env python3
"""Parameterized weakening patcher for SHAMATA (NIST SHA-3 Round 1).

Reduces the number of FINALIZATION rounds of the hash. In
`ShamataReference.c :: Final()`, after padding, the compression function
`UpdateRegister` is applied a fixed number of times using the processed
message-block count as the data block:

    // Call UpdateRegister 32 times using the number of message blocks as block
    for(i=0;i<32;i++)
        UpdateRegister(state,RData,state->r,i+1);

This 32-iteration loop is the dominant output-mixing / finalization step: it
performs the bulk of the state diffusion that a collision (in the linear
message injection) must survive. Reducing the count from the full-strength 32
weakens avalanche so that reduced-round differential / birthday collisions
become findable — the intended weakening for the deliberately-easier T2 bands.

The security knob is that loop's iteration bound. Note the source contains a
SECOND `i<32` loop a few lines above (`for(i=16;i<32;i++)` copying the last
128 bits of the padded remainder into RData) which must NOT be touched, so we
match ONLY the loop that (a) starts at `i=0` AND (b) is immediately followed
by an `UpdateRegister(...)` call. The reference file path contains spaces
("SHAMATA Tubitak UEKAE/Reference Implementation/ShamataReference.c"), which is
why this is a patcher rather than a unified diff.

Usage:  patch_shamata.py <file> <rounds>

Asserts EXACTLY 1 finalization loop was rewritten; fails loudly otherwise so a
silent unweakened variant can never be produced.
"""

import re
import sys

# Finalization loop: `for ( i = 0 ; i < 32 ; i++ )`, flexible whitespace.
# `prefix`/`tail` capture everything except the literal bound `32`, so the
# substitution swaps only the digit and preserves the original whitespace.
LOOP_RE = re.compile(
    r"^(?P<prefix>\s*for\s*\(\s*i\s*=\s*0\s*;\s*i\s*<\s*)32(?P<tail>\s*;\s*i\+\+\s*\).*)$"
)
# Anchor: the loop body must call UpdateRegister on the next non-blank line.
BODY_RE = re.compile(r"^\s*UpdateRegister\s*\(")


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_shamata.py <file> <rounds>\n")
        return 2
    path = sys.argv[1]
    rounds = int(sys.argv[2])
    if not (1 <= rounds < 32):
        sys.stderr.write(
            "error: rounds must satisfy 1 <= rounds < 32 (full strength)\n"
        )
        return 2

    with open(path, "r") as fh:
        lines = fh.readlines()

    def next_nonblank(start):
        j = start
        while j < len(lines) and lines[j].strip() in ("", "{"):
            j += 1
        return j

    changed = 0
    for idx, line in enumerate(lines):
        m = LOOP_RE.match(line.rstrip("\n"))
        if not m:
            continue
        nb = next_nonblank(idx + 1)
        if nb >= len(lines) or not BODY_RE.match(lines[nb].rstrip("\n")):
            continue
        newline = "{}{}{}".format(m.group("prefix"), rounds, m.group("tail"))
        if line.endswith("\n"):
            newline += "\n"
        lines[idx] = newline
        changed += 1

    if changed != 1:
        sys.stderr.write(
            "FATAL: expected to patch exactly 1 finalization loop, "
            "patched {}. Refusing to write (upstream drift?).\n".format(changed)
        )
        return 1

    with open(path, "w") as fh:
        fh.writelines(lines)

    sys.stderr.write(
        "patched finalization loop to {} rounds in {}\n".format(rounds, path)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
