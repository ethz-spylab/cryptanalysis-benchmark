#!/usr/bin/env python3
"""Scale down Gravity-SPHINCS by reducing the digest size HASH_SIZE.

Usage:
    patch_gravity_sphincs.py <Reference_Implementation_dir> <HASH_SIZE_bytes>

Reducing HASH_SIZE lowers the generic-forgery work factor to ~2^(8*HASH_SIZE)
(see algorithm_scaling_down/nist_pqc/gravity_sphincs.txt). HASH_SIZE is *not* a
clean one-liner: the reference hardwires 256-bit Haraka / SHA-256 and a 32-byte
digest in several places. This patcher applies the minimal coordinated set of
edits required to keep sign/verify a correct round-trip for HASH_SIZE < 32:

  common.h        : #define HASH_SIZE -> band value
  common.h        : WOTS_ell1 = 2*HASH_SIZE  (WOTS+ has 2 base-16 digits per
                    digest byte; the original 64 over-reads the digest)
  hash.h          : drop __attribute__((aligned(16))) so sizeof(struct hash)
                    == HASH_SIZE and every contiguity assumption (hashcpyN,
                    hash_compress_all, ...) holds as upstream intends
  primitives/hash.c: the four hash wrappers hash into a 32-byte (resp. 64-byte
                    zero-padded input) scratch buffer and keep only HASH_SIZE
                    bytes; hash_N_to_N_chain iterates the single-step truncating
                    hash so H^(w-1-d)(H^d(x)) == H^(w-1)(x) (a full-state
                    haraka chain would truncate only at the end and break WOTS+)
  primitives/aes.c: zero-extend the HASH_SIZE-byte digest used as an AES-256 key
                    to 32 bytes (callers pass a struct hash as the key)
  api.h           : derive CRYPTO_SECRETKEYBYTES / CRYPTO_PUBLICKEYBYTES /
                    CRYPTO_BYTES from the actual structs so the unmodified cli.c
                    uses sizes that track HASH_SIZE

Every substitution asserts it changed something; the script fails loudly if an
anchor is missing (e.g. run against an already-patched or unexpected tree).
"""
import os
import re
import sys


def sub_once(text, pattern, repl, what, flags=0, count=1):
    new, n = re.subn(pattern, repl, text, count=count, flags=flags)
    if n == 0:
        raise SystemExit(f"FATAL: no substitution for '{what}' (0 changes)")
    return new


def patch_file(path, fn, what):
    with open(path) as f:
        s = f.read()
    s2 = fn(s)
    if s2 == s:
        raise SystemExit(f"FATAL: '{what}' left {path} unchanged")
    with open(path, "w") as f:
        f.write(s2)
    print(f"  patched {what}: {os.path.relpath(path)}")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    ref = sys.argv[1]
    hs = int(sys.argv[2])
    if not (1 <= hs < 32):
        raise SystemExit(f"FATAL: HASH_SIZE must be in [1,31], got {hs}")

    common_h = os.path.join(ref, "common.h")
    hash_h = os.path.join(ref, "hash.h")
    hash_c = os.path.join(ref, "primitives", "hash.c")
    aes_c = os.path.join(ref, "primitives", "aes.c")
    api_h = os.path.join(ref, "api.h")
    for p in (common_h, hash_h, hash_c, aes_c, api_h):
        if not os.path.isfile(p):
            raise SystemExit(f"FATAL: expected file missing: {p}")

    # 1) common.h: HASH_SIZE + WOTS_ell1
    def fix_common(s):
        s = sub_once(s, r"^#define HASH_SIZE 32$",
                     f"#define HASH_SIZE {hs}", "common.h HASH_SIZE",
                     flags=re.M)
        s = sub_once(
            s,
            r"^#define WOTS_ell1 \(1 << \(WOTS_LOG_ell1\)\)$",
            "#define WOTS_ell1 (2 * (HASH_SIZE))  "
            "/* 2 base-16 WOTS digits per digest byte */",
            "common.h WOTS_ell1", flags=re.M)
        return s

    patch_file(common_h, fix_common, "common.h")

    # 2) hash.h: drop alignment so sizeof(struct hash) == HASH_SIZE
    def fix_hash_h(s):
        return sub_once(
            s,
            r"\} __attribute__ \(\(aligned \(16\)\)\);",
            "};", "hash.h drop aligned(16)")

    patch_file(hash_h, fix_hash_h, "hash.h")

    # 3) primitives/hash.c: rewrite the four wrappers
    new_wrappers = '''void hash_N_to_N(struct hash *dst, const struct hash *src)
{
    uint8_t in[32] = {0};
    uint8_t out[32];
    memcpy(in, src->h, HASH_SIZE);
    haraka256_256(out, in);
    memcpy(dst->h, out, HASH_SIZE);
}

void hash_N_to_N_chain(struct hash *dst, const struct hash *src, int chainlen)
{
    /* Iterate the single-step (HASH_SIZE-truncating) hash so the chain is
       well-defined over HASH_SIZE-byte values: H^(w-1-d)(H^d(x)) == H^(w-1)(x).
       haraka256_256_chain keeps full 32-byte state and only truncates at the
       end, which would break WOTS+ for HASH_SIZE < 32. */
    struct hash cur;
    int i;
    memcpy(cur.h, src->h, HASH_SIZE);
    for (i = 0; i < chainlen; ++i) {
        struct hash next;
        hash_N_to_N(&next, &cur);
        memcpy(cur.h, next.h, HASH_SIZE);
    }
    memcpy(dst->h, cur.h, HASH_SIZE);
}

void hash_2N_to_N(struct hash *dst, const struct hash *src)
{
    uint8_t in[64] = {0};
    uint8_t out[32];
    memcpy(in, src[0].h, HASH_SIZE);
    memcpy(in + HASH_SIZE, src[1].h, HASH_SIZE);
    haraka512_256(out, in);
    memcpy(dst->h, out, HASH_SIZE);
}

void hash_to_N(struct hash *dst, const uint8_t *src, uint64_t srclen)
{
    uint8_t out[32];
    SHA256(src, srclen, out);
    memcpy(dst->h, out, HASH_SIZE);
}
'''

    def fix_hash_c(s):
        return sub_once(
            s,
            r"void hash_N_to_N\(struct hash \*dst.*?\nvoid hash_to_N\(.*?\n\}\n",
            lambda _m: new_wrappers,
            "hash.c wrappers", flags=re.S)

    patch_file(hash_c, fix_hash_c, "primitives/hash.c")

    # 4) primitives/aes.c: zero-extend the digest key to a 32-byte AES-256 key
    def fix_aes_c(s):
        s = sub_once(
            s,
            r'#include "\.\./aes\.h"\n',
            '#include "../aes.h"\n#include "../common.h"\n',
            "aes.c include common.h")
        anchor = (
            "    if (bytes == 0) return 0;\n\n"
            "    if (!(ctx = EVP_CIPHER_CTX_new ())) {")
        if anchor not in s:
            raise SystemExit("FATAL: aes.c body anchor not found")
        s = s.replace(
            anchor,
            "    /* Callers pass a HASH_SIZE-byte digest as the key; zero-extend\n"
            "       it to the 32-byte AES-256 key so reduced HASH_SIZE builds do\n"
            "       not over-read. */\n"
            "    uint8_t key32[32] = {0};\n"
            "    memcpy (key32, sk, HASH_SIZE < 32 ? HASH_SIZE : 32);\n\n"
            + anchor, 1)
        s = sub_once(
            s,
            r"EVP_EncryptInit_ex \(ctx, EVP_aes_256_ctr \(\), NULL, sk, counter\)",
            "EVP_EncryptInit_ex (ctx, EVP_aes_256_ctr (), NULL, key32, counter)",
            "aes.c use key32")
        return s

    patch_file(aes_c, fix_aes_c, "primitives/aes.c")

    # 5) api.h: derive CRYPTO_* sizes from the actual structs
    def fix_api_h(s):
        repl = (
            "#ifndef CRYPTO_BYTES\n"
            "/* Sizes derived from the actual structs so they track HASH_SIZE. */\n"
            "#include \"gravity.h\"\n"
            "#define CRYPTO_ALGNAME \"Gravity-SPHINCS S\"\n"
            "#define CRYPTO_SECRETKEYBYTES ((int) sizeof (struct gravity_sk))\n"
            "#define CRYPTO_PUBLICKEYBYTES ((int) (HASH_SIZE))\n"
            "#define CRYPTO_BYTES ((int) sizeof (struct gravity_sign))\n"
            "#endif\n")
        return sub_once(
            s,
            r"#ifndef CRYPTO_BYTES\n.*\n#endif\n",
            lambda _m: repl,
            "api.h size macros", flags=re.S)

    patch_file(api_h, fix_api_h, "api.h")

    print(f"OK: Gravity-SPHINCS scaled to HASH_SIZE={hs} "
          f"(n={8 * hs} bits, ~2^{8 * hs} generic forgery)")


if __name__ == "__main__":
    main()
