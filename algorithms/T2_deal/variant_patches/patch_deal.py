#!/usr/bin/env python3
"""Reduce the DEAL-128 Feistel round count in deal.c.

DEAL-128 (the CLI's only key length, k_len == 2) is a 6-round Feistel whose
round function is single-DES. The reference implementation (deal.c) UNROLLS the
rounds instead of using a `#define`/loop, so the round count is expressed as a
sequence of `des_ecm(<var>, c, l_key + <off>);` calls with offsets
0, 32, 64, 96, 128, 160 in BOTH encrypt() and decrypt():

  encrypt round i (i=1..6) -> l_key + 32*(i-1)   (in order)
  decrypt undoes them in reverse: l_key + 160,128,96,64,32,0

To make a valid R-round Feistel we KEEP encrypt rounds 1..R (offsets
0..32*(R-1)) and the matching decrypt reversals (the SAME offsets), and DROP
every round with offset >= 32*R. Because each surviving decrypt line reverses
the corresponding surviving encrypt line, the reduced cipher still round-trips
(encrypt then decrypt recovers the plaintext).

Removing all `des_ecm(... l_key + <off>) ...` CALL lines whose offset >= 32*R
(and <= 160, i.e. the k_len==2 path only) deletes exactly (6-R) lines from
encrypt and (6-R) from decrypt = 2*(6-R) lines total. The k_len==4 blocks
(offsets 192, 224) are never reached by the 128-bit CLI and are left untouched;
the `des_ky(... l_key + <off>)` key-schedule lines in set_key() are also left
untouched (unused surviving subkeys are harmless). The forward declaration
`void des_ecm(...)` has no `l_key` and is not matched.

Usage: patch_deal.py <path/to/deal.c> <rounds>
Asserts exactly 2*(6-R) call lines were removed; fails loudly otherwise so a
mis-apply can never silently ship an unweakened variant.
"""

import re
import sys

BASE_ROUNDS = 6

CALL_RE = re.compile(r"des_ecm\(\s*[ab]\s*,\s*c\s*,\s*l_key\s*\+\s*(\d+)\s*\)\s*;")


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_deal.py <deal.c> <rounds>\n")
        return 2
    path = sys.argv[1]
    rounds = int(sys.argv[2])
    if not (1 <= rounds < BASE_ROUNDS):
        sys.stderr.write(
            f"rounds must be in [1, {BASE_ROUNDS - 1}] (strictly weaker than "
            f"base {BASE_ROUNDS}); got {rounds}\n"
        )
        return 2

    # Offsets to remove: the k_len==2 unrolled rounds R..6 (0-indexed 32*R..160).
    remove_offsets = {32 * i for i in range(rounds, BASE_ROUNDS)}  # {32R,...,160}

    with open(path, "r") as f:
        lines = f.readlines()

    out = []
    removed = 0
    for line in lines:
        m = CALL_RE.search(line)
        if m and int(m.group(1)) in remove_offsets:
            removed += 1
            continue
        out.append(line)

    expected = 2 * (BASE_ROUNDS - rounds)
    if removed != expected:
        sys.stderr.write(
            f"FATAL: expected to remove {expected} des_ecm call lines for "
            f"rounds={rounds}, but removed {removed}. Source layout changed?\n"
        )
        return 1

    with open(path, "w") as f:
        f.writelines(out)

    sys.stderr.write(
        f"patch_deal: reduced DEAL-128 to {rounds} rounds "
        f"(removed {removed} des_ecm call lines)\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
