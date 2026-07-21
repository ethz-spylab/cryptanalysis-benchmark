#!/usr/bin/env python3
"""Patch Ding Key Exchange's ring dimension N (the single lattice-security knob).

Ding Key Exchange is a Ring-LWE KEM in R_q = Z_q[x]/(x^N + 1). Lattice-attack
cost is set by the BKZ block size beta required at dimension N for the fixed
q/sigma; reducing N is the clean monotone weakening knob (see
algorithm_scaling_down/nist_pqc/ding_key_exchange.txt). q (120833) and sigma
(4.19) are held fixed so the hard-wired discrete-Gaussian CDT tables and the
reconciliation arithmetic stay correct; correctness is per-coordinate and
essentially independent of N, so smaller N still decrypts.

Three coupled edits are required, all confined to Reference_Implementation/:
  * api.h : `#define N 512` -> `#define N <n>`. All key/ciphertext byte sizes
    (CRYPTO_*BYTES) are defined in terms of N, so they update automatically.
  * kem.c : the discrete-Gaussian CDT sampling tables are guarded by a hard
    `#if N == 512` (else branch = the N=1024 tables). For any N not in
    {512,1024} that else branch would silently swap in the wrong-sigma 1024
    tables. Since sigma is unchanged, the 512 tables stay valid for any smaller
    N, so the guard is relaxed to `#if N <= 512` to keep the 512 block live.
  * kem.c : two runtime sigma-selection guards `if(n == 512)` (in keypair and
    enc) pick sigma_se_512; the `else if(n == 1024)` / `else { error; exit }`
    chain would abort for any other N. Relaxed to `if(n <= 512)` so sigma stays
    sigma_se_512 = 4.19 for every band.

Usage: patch_ding.py <path/to/Reference_Implementation> <N>

Fails loudly (non-zero exit) if any expected substitution makes zero changes,
so a botched patch can never silently yield an unweakened variant.
"""
import os
import re
import sys


def patch_file(path, pattern, replacement, label, expected=None):
    with open(path, "rb") as f:
        data = f.read()
    new_data, n = pattern.subn(replacement, data)
    if n == 0:
        sys.stderr.write(
            f"FATAL: pattern for {label} not found in {path}; nothing patched\n"
        )
        sys.exit(1)
    if expected is not None and n != expected:
        sys.stderr.write(
            f"FATAL: pattern for {label} matched {n} times, expected {expected}\n"
        )
        sys.exit(1)
    with open(path, "wb") as f:
        f.write(new_data)
    return n


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(
            "usage: patch_ding.py <Reference_Implementation dir> <N>\n"
        )
        return 2

    ref_dir = sys.argv[1]
    nval = int(sys.argv[2])
    # Ring dimension must be positive and not exceed the full-strength 512 set
    # (the 512 CDT tables are reused; larger N would need the 1024 tables/sigma).
    if not (1 <= nval <= 512):
        sys.stderr.write(f"FATAL: N={nval} outside valid range [1, 512]\n")
        return 2

    api_path = os.path.join(ref_dir, "api.h")
    kem_path = os.path.join(ref_dir, "kem.c")
    for p in (api_path, kem_path):
        if not os.path.isfile(p):
            sys.stderr.write(f"FATAL: expected source file missing: {p}\n")
            return 1

    # api.h: set the ring dimension.
    patch_file(
        api_path,
        re.compile(rb"#define\s+N\s+512\b"),
        b"#define N %d" % nval,
        "api.h #define N",
        expected=1,
    )

    # kem.c: relax the compile-time CDT-table guard to keep the 512 tables live.
    patch_file(
        kem_path,
        re.compile(rb"#if\s+N\s*==\s*512\b"),
        b"#if N <= 512",
        "kem.c #if N == 512 (CDT tables)",
        expected=1,
    )

    # kem.c: relax the two runtime sigma-selection guards (keypair + enc).
    patch_file(
        kem_path,
        re.compile(rb"if\s*\(\s*n\s*==\s*512\s*\)"),
        b"if(n <= 512)",
        "kem.c if(n == 512) (sigma selection)",
        expected=2,
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
