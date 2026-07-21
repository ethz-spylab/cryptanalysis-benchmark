#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download and extract Ding Key Exchange sources
# wget https://csrc.nist.gov/CSRC/media/Projects/Post-Quantum-Cryptography/documents/round-1/submissions/Ding_LWE_Key_Exchange.zip
unzip -o Ding_LWE_Key_Exchange.zip

# Copy the chosen parameter set's sources (Reference_Implementation) plus the
# shared NIST RNG from KAT/ into the build directory. The parameter set is
# selected by the `#define N` in api.h; the smallest set (N=512, the upstream
# default == the PQCkemKAT_1536 KAT) is used as-is.
cp Reference_Implementation/*.c .
cp Reference_Implementation/*.h .
cp KAT/rng.c KAT/rng.h .

# Remove the KAT generation file (has its own main)
rm -f PQCgenKAT_kem.c

# Install necessary dependencies:
#   - NTL + GMP: kem.c is C++ and uses the NTL number-theory library
#   - OpenSSL: rng.c implements the NIST AES-CTR DRBG via libcrypto
apt-get update
apt-get install -y libntl-dev libgmp-dev libssl-dev

# kem.c is C++ (NTL); cli.c and rng.c are C. We cannot edit the upstream api.h
# (it declares crypto_kem_* with C++ linkage when kem.c is compiled by g++) or
# kem.c, so we bridge the two languages with a tiny generated C++ shim that
# re-exports the C++-compiled crypto_kem_* / randombytes symbols under C linkage
# for cli.c. The shim is created here via heredoc, not by editing upstream.
# The shim declares the C++-mangled crypto_kem_* (as defined in kem.o, compiled
# by g++) and re-exports them under C linkage with the *same* names, so cli.o
# (compiled as C, referencing unmangled crypto_kem_*) links cleanly. We do NOT
# include the upstream api.h here (that would declare the names with C++ linkage
# and clash); we hand-write the three prototypes both ways.
# kem.c (g++) references crypto_kem_* and randombytes with C++ linkage, so rng.c
# is also built with g++ (the upstream KAT Makefile does the same), leaving every
# kem.o<->rng.o symbol C++-mangled and consistent. cli.c (C) instead needs
# unmangled crypto_kem_* / randombytes_init; this shim re-exports those few
# entry points under C linkage. Distinct mangling => no symbol clash.
cat > kem_c_shim.cpp <<'EOF'
// C++-mangled symbols actually defined in kem.o / rng.o (g++-compiled).
int crypto_kem_keypair(unsigned char *pk, unsigned char *sk);
int crypto_kem_enc(unsigned char *ct, unsigned char *ss, const unsigned char *pk);
int crypto_kem_dec(unsigned char *ss, const unsigned char *ct, const unsigned char *sk);
void randombytes_init(unsigned char *entropy_input,
                      unsigned char *personalization_string,
                      int security_strength);

// C-linkage wrappers consumed by cli.o (C). Different mangling => no clash.
extern "C" int crypto_kem_keypair_c(unsigned char *pk, unsigned char *sk) {
    return crypto_kem_keypair(pk, sk);
}
extern "C" int crypto_kem_enc_c(unsigned char *ct, unsigned char *ss, const unsigned char *pk) {
    return crypto_kem_enc(ct, ss, pk);
}
extern "C" int crypto_kem_dec_c(unsigned char *ss, const unsigned char *ct, const unsigned char *sk) {
    return crypto_kem_dec(ss, ct, sk);
}
extern "C" void randombytes_init_c(unsigned char *entropy_input,
                                   unsigned char *personalization_string,
                                   int security_strength) {
    randombytes_init(entropy_input, personalization_string, security_strength);
}
EOF

# Compile each translation unit with the right compiler:
#   - kem.c with g++ (C++/NTL)
#   - rng.c and cli.c with gcc (C); rng.c's randombytes* already have C linkage
#   - the shim with g++; it forwards C-linkage names to the C++ crypto_kem_*
# Link everything with g++ so the C++ runtime / NTL are pulled in.
# Redirect cli.c's crypto_kem_* calls (and api.h's prototypes) to the C-linkage
# wrappers via -D, so cli.c stays byte-identical to the canonical KEM template
# on disk while linking against the C++ implementation through the shim.
gcc  -O2 -fcommon -I. \
     -Dcrypto_kem_keypair=crypto_kem_keypair_c \
     -Dcrypto_kem_enc=crypto_kem_enc_c \
     -Dcrypto_kem_dec=crypto_kem_dec_c \
     -Drandombytes_init=randombytes_init_c \
     -c cli.c -o cli.o
g++  -O2 -fcommon -I. -c rng.c -o rng.o
g++  -O2 -fcommon -I. -c kem.c -o kem.o
g++  -O2 -fcommon -I. -c kem_c_shim.cpp -o kem_c_shim.o
g++  -O2 -o cli cli.o rng.o kem.o kem_c_shim.o -lntl -lgmp -lssl -lcrypto

echo "Build complete. CLI binary created at: $SCRIPT_DIR/cli"
