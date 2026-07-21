/*
 * C-linkage bridge for the LOCKER KEM.
 *
 * The upstream reference implementation is C++ (kem.cpp etc.) and its api.h
 * declares crypto_kem_keypair / crypto_kem_enc / crypto_kem_dec WITHOUT
 * extern "C", so compiled by g++ those symbols get C++-mangled names. Our
 * cli.c is plain C (it relies on C semantics such as implicit void* casts in
 * argp), so it references the UNMANGLED C symbols.
 *
 * This bridge is compiled as C++ (so it can call the mangled upstream
 * functions) but exports thin wrappers with extern "C" linkage that cli.c
 * links against. This keeps the upstream sources untouched.
 */

#include "api.h"
#include "rng.h"

/* Mangled (C++) declarations as provided by the upstream api.h, included above
 * without extern "C": the prototypes below are emitted by the compiler as the
 * C++ symbols defined in kem.cpp. We just forward to them under C linkage. */

extern "C" int locker_crypto_kem_keypair(unsigned char *pk, unsigned char *sk) {
  return crypto_kem_keypair(pk, sk);
}

extern "C" int locker_crypto_kem_enc(unsigned char *ct, unsigned char *ss,
                                     const unsigned char *pk) {
  return crypto_kem_enc(ct, ss, pk);
}

extern "C" int locker_crypto_kem_dec(unsigned char *ss, const unsigned char *ct,
                                     const unsigned char *sk) {
  return crypto_kem_dec(ss, ct, sk);
}

/* rng.c is compiled by g++ as well (upstream uses CC=g++), so randombytes_init
 * is also C++-mangled. Bridge it to C linkage for cli.c's init_rng(). */
extern "C" void locker_randombytes_init(unsigned char *entropy_input,
                                        unsigned char *personalization_string,
                                        int security_strength) {
  randombytes_init(entropy_input, personalization_string, security_strength);
}
