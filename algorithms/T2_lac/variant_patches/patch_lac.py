#!/usr/bin/env python3
"""Generation-time weakening patcher for T2_lac.

Sets NUM_ONE (Hamming weight of the signed-binary noise vector) inside the
LAC128 parameter block of LAC-v3a/ref/lac_param.h. This reproduces, byte for
byte, the edit the old build-time apply_variant_patch.sh performed (tr -d '\\r'
followed by an awk targeting only the #if defined(LAC128) ... #endif block).

Usage: patch_lac.py <path/to/lac_param.h> <NUM_ONE>

Fails loudly (exit 1) unless exactly one substitution is made inside the
LAC128 block, so a missing/renamed block can never yield a silent unweakened
variant.
"""
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: patch_lac.py <lac_param.h> <NUM_ONE>\n")
        sys.exit(2)
    path = sys.argv[1]
    num_one = sys.argv[2].encode()

    with open(path, "rb") as f:
        raw = f.read()

    # Mirror the old helper's `tr -d '\r'`: normalise CRLF -> LF wholesale.
    text = raw.replace(b"\r", b"")
    lines = text.split(b"\n")

    in_lac128 = False
    count = 0
    out = []
    for line in lines:
        if line.startswith(b"#if defined(LAC128)"):
            in_lac128 = True
        elif line.startswith(b"#endif"):
            in_lac128 = False
        if in_lac128 and line.startswith(b"#define NUM_ONE "):
            out.append(b"#define NUM_ONE " + num_one
                       + b" //number of 1 or -1 in noise vector")
            count += 1
            continue
        out.append(line)

    if count != 1:
        sys.stderr.write(
            "patch_lac.py: expected exactly 1 NUM_ONE substitution in the "
            "LAC128 block, made %d\n" % count)
        sys.exit(1)

    with open(path, "wb") as f:
        f.write(b"\n".join(out))


if __name__ == "__main__":
    main()
