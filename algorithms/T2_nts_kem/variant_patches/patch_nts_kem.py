#!/usr/bin/env python3
"""
Parameter-reduction patcher for NTS-KEM (NIST PQC Round 1, NTS-KEM(12,64)).

Usage:
    patch_nts_kem.py <path/to/nts_kem_params.h> <T>

The only security knob is the Goppa error-correction parameter T (number of
correctable errors / Goppa degree). Full strength is T=64. The field exponent
M=12 (GF(2^12), N=4096) is held FIXED — changing M would change the byte-packing
stride and break the clean closed-form constants below.

Every derived #define in nts_kem_params.h is regenerated from T via the exact
formulas cross-checked against all three shipped NTS-KEM parameter sets. Because
the upstream splits the same size constants across two headers, the sibling
`api.h` (CRYPTO_PUBLICKEYBYTES / CRYPTO_SECRETKEYBYTES / CRYPTO_CIPHERTEXTBYTES /
CRYPTO_BYTES) is regenerated in lockstep — kem.c memcpy's CRYPTO_PUBLICKEYBYTES
bytes out of an NTS_KEM_PUBLIC_KEY_SIZE buffer, and cli.c validates I/O lengths
against the api.h macros, so the two headers must agree or the build/round-trip
breaks.

A self-check guarantees T=64 reproduces the exact shipped values before any file
is written; mismatch aborts (non-zero exit) so generation never ships a wrong
instance.
"""
import os
import re
import sys


def ceil_div(a, b):
    return -(-a // b)


def compute_params(T):
    """Return (params_defines, api_defines) dicts for a given T, with M=12 fixed."""
    M = 12
    N = 4096                       # 2**M
    R = M * T
    K = N - R                      # = 4096 - 12*T
    A = K - 256
    B = 256
    C = R                          # = 12*T
    BC = B + R                     # = 256 + 12*T
    R_DIV_64 = ceil_div(R, 64)     # ceil! e.g. T=64 -> 12
    CEIL_N_BYTE = ceil_div(N, 8)   # = 512
    CEIL_K_BYTE = ceil_div(K, 8)
    CEIL_R_BYTE = ceil_div(R, 8)
    PUBLIC_KEY_SIZE = K * CEIL_R_BYTE
    CIPHERTEXT_SIZE = 32 + CEIL_R_BYTE
    PRIVATE_KEY_SIZE = (2 * BC + N) * 3 // 2   # integer for all valid T (M=12 pack stride)
    KEY_SIZE = 32

    params = {
        "NTS_KEM_KEY_SIZE": KEY_SIZE,
        "NTS_KEM_PARAM_M": M,
        "NTS_KEM_PARAM_T": T,
        "NTS_KEM_PARAM_N": N,
        "NTS_KEM_PARAM_K": K,
        "NTS_KEM_PARAM_A": A,
        "NTS_KEM_PARAM_B": B,
        "NTS_KEM_PARAM_C": C,
        "NTS_KEM_PARAM_BC": BC,
        "NTS_KEM_PARAM_R_DIV_64": R_DIV_64,
        "NTS_KEM_PARAM_CEIL_N_BYTE": CEIL_N_BYTE,
        "NTS_KEM_PARAM_CEIL_K_BYTE": CEIL_K_BYTE,
        "NTS_KEM_PARAM_CEIL_R_BYTE": CEIL_R_BYTE,
        "NTS_KEM_PRIVATE_KEY_SIZE": PRIVATE_KEY_SIZE,
        "NTS_KEM_PUBLIC_KEY_SIZE": PUBLIC_KEY_SIZE,
        "NTS_KEM_CIPHERTEXT_SIZE": CIPHERTEXT_SIZE,
    }
    api = {
        "CRYPTO_BYTES": KEY_SIZE,
        "CRYPTO_SECRETKEYBYTES": PRIVATE_KEY_SIZE,
        "CRYPTO_PUBLICKEYBYTES": PUBLIC_KEY_SIZE,
        "CRYPTO_CIPHERTEXTBYTES": CIPHERTEXT_SIZE,
    }
    return params, api


# Authoritative shipped NTS-KEM(12,64) values — the self-check target.
SHIPPED_T64 = {
    "NTS_KEM_KEY_SIZE": 32,
    "NTS_KEM_PARAM_M": 12,
    "NTS_KEM_PARAM_T": 64,
    "NTS_KEM_PARAM_N": 4096,
    "NTS_KEM_PARAM_K": 3328,
    "NTS_KEM_PARAM_A": 3072,
    "NTS_KEM_PARAM_B": 256,
    "NTS_KEM_PARAM_C": 768,
    "NTS_KEM_PARAM_BC": 1024,
    "NTS_KEM_PARAM_R_DIV_64": 12,
    "NTS_KEM_PARAM_CEIL_N_BYTE": 512,
    "NTS_KEM_PARAM_CEIL_K_BYTE": 416,
    "NTS_KEM_PARAM_CEIL_R_BYTE": 96,
    "NTS_KEM_PRIVATE_KEY_SIZE": 9216,
    "NTS_KEM_PUBLIC_KEY_SIZE": 319488,
    "NTS_KEM_CIPHERTEXT_SIZE": 128,
}


def self_check():
    params, _ = compute_params(64)
    if params != SHIPPED_T64:
        diffs = {k: (params.get(k), SHIPPED_T64.get(k))
                 for k in SHIPPED_T64 if params.get(k) != SHIPPED_T64.get(k)}
        sys.exit("FATAL self-check: T=64 does not reproduce shipped values: %r" % diffs)


def patch_defines(path, mapping):
    """Replace each `#define NAME <value>` in `path` according to `mapping`.

    Whitespace between NAME and value is arbitrary (the upstream uses spaces and
    a tab). Fails loudly if any expected define is missing.
    """
    with open(path, "r") as fh:
        text = fh.read()

    for name, value in mapping.items():
        pattern = re.compile(r"(^[ \t]*#define[ \t]+" + re.escape(name) + r"[ \t]+)\S+",
                             re.MULTILINE)
        new_text, n = pattern.subn(lambda m: m.group(1) + str(value), text)
        if n == 0:
            sys.exit("FATAL: #define %s not found in %s" % (name, path))
        text = new_text

    with open(path, "w") as fh:
        fh.write(text)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: patch_nts_kem.py <nts_kem_params.h> <T>")
    params_path = sys.argv[1]
    T = int(sys.argv[2])

    self_check()

    if not (0 < T < 64):
        sys.exit("FATAL: T=%d out of range (must be a weakening: 0 < T < 64)" % T)

    params, api = compute_params(T)

    # Patch nts_kem_params.h (the real algorithmic parameters).
    patch_defines(params_path, params)

    # Patch the sibling api.h in lockstep (CLI buffer sizes / length validation).
    api_path = os.path.join(os.path.dirname(params_path), "api.h")
    if not os.path.exists(api_path):
        sys.exit("FATAL: sibling api.h not found next to %s" % params_path)
    patch_defines(api_path, api)

    # Verify the write took effect for the headline parameter (defence in depth).
    with open(params_path) as fh:
        body = fh.read()
    expect_k = re.search(r"#define[ \t]+NTS_KEM_PARAM_K[ \t]+(\d+)", body)
    if not expect_k or int(expect_k.group(1)) != params["NTS_KEM_PARAM_K"]:
        sys.exit("FATAL: post-patch K mismatch in %s (expected %d)"
                 % (params_path, params["NTS_KEM_PARAM_K"]))

    print("patched T=%d : N=%d K=%d d=%d  PK=%d SK=%d CT=%d"
          % (T, params["NTS_KEM_PARAM_N"], params["NTS_KEM_PARAM_K"],
             2 * T + 1, params["NTS_KEM_PUBLIC_KEY_SIZE"],
             params["NTS_KEM_PRIVATE_KEY_SIZE"], params["NTS_KEM_CIPHERTEXT_SIZE"]))


if __name__ == "__main__":
    main()
