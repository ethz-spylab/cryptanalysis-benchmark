#!/usr/bin/env python3
"""Parameterized weakening patcher for Dynamic SHA2 (NIST SHA-3 Round 1).

Reduces the OUTER round count of BOTH compression functions
(sha32_compile -> 256-bit default digest, sha64_compile -> 512-bit digest)
from the full-strength value 8 down to a chosen band value.

The security knob is the outer loop:

    for ( i=0; i<8; i++ ) {        // sha32_compile  (line ~195)
        for (i1=0; i1<9; i1=i1+8)
            ...

    for (i=0;i<8;i++)              // sha64_compile  (line ~293)
        for (i1=0;i1<9;i1=i1+8)
            ...

Note the two occurrences differ in whitespace, so we cannot match a fixed
literal. We match the outer `for (i=0; i<8; i++)` loop ONLY when the next
non-blank line is the step-8 inner loop `for (i1=0; i1<9; i1=i1+8)`. This
distinguishes the two real compression outer loops from the many other
`for (i=0; i<8; i++)` initialization loops over the eight hash words (whose
bodies are `ch[i]=...` / `hash_*[i] += ...`, never the i1 step-8 loop), and
from the `if (i==0)` inner loops which use `i1<9; i1++` (step 1, not step 8).

Usage:  patch_dynamicsha2.py <file> <rounds>

Asserts EXACTLY 2 outer loops were rewritten; fails loudly otherwise so a
silent unweakened variant can never be produced.
"""
import re
import sys

# Outer compression loop: `for ( i = 0 ; i < 8 ; i++ )`, flexible whitespace.
# `prefix` and `tail` capture everything except the literal bound `8`, so the
# substitution swaps only the digit and preserves the original whitespace.
OUTER_RE = re.compile(
    r"^(?P<prefix>\s*for\s*\(\s*i\s*=\s*0\s*;\s*i\s*<\s*)8(?P<tail>\s*;\s*i\+\+\s*\).*)$"
)
# Anchor: step-8 inner loop `for (i1=0; i1<9; i1=i1+8)`, flexible whitespace.
INNER_RE = re.compile(
    r"^\s*for\s*\(\s*i1\s*=\s*0\s*;\s*i1\s*<\s*9\s*;\s*i1\s*=\s*i1\s*\+\s*8\s*\)"
)


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_dynamicsha2.py <file> <rounds>\n")
        return 2
    path = sys.argv[1]
    rounds = int(sys.argv[2])
    if not (1 <= rounds < 8):
        sys.stderr.write(
            "error: rounds must satisfy 1 <= rounds < 8 (full strength)\n"
        )
        return 2

    with open(path, "r") as fh:
        lines = fh.readlines()

    def next_anchor(start):
        # Skip blank lines and a lone opening brace `{` (sha64_compile puts the
        # outer loop's `{` on its own line; sha32_compile puts it inline).
        j = start
        while j < len(lines) and lines[j].strip() in ("", "{"):
            j += 1
        return j

    changed = 0
    for idx, line in enumerate(lines):
        m = OUTER_RE.match(line.rstrip("\n"))
        if not m:
            continue
        nb = next_anchor(idx + 1)
        if nb >= len(lines) or not INNER_RE.match(lines[nb].rstrip("\n")):
            continue
        newline = "{}{}{}".format(m.group("prefix"), rounds, m.group("tail"))
        # Preserve any trailing newline.
        if line.endswith("\n"):
            newline += "\n"
        lines[idx] = newline
        changed += 1

    if changed != 2:
        sys.stderr.write(
            "FATAL: expected to patch exactly 2 outer round loops, "
            "patched {}. Refusing to write (upstream drift?).\n".format(changed)
        )
        return 1

    with open(path, "w") as fh:
        fh.writelines(lines)

    sys.stderr.write(
        "patched 2 outer round loops to count {} in {}\n".format(rounds, path)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
