/* ---------------------------------------------------------------------------
 * Self-contained standard DES (FIPS 46) providing the exact API that Brian
 * Gladman's deal.c expects from its sibling "../des/des.h":
 *
 *     void des_ky(const u4byte key[2], u4byte ks[32]);   // key schedule
 *     void des_ec(const u4byte in[2], u4byte out[2],     // single-block
 *                 const u4byte ks[32]);                  //   DES encrypt
 *
 * deal.c is compiled with MODIFIED_DES *undefined* (see build_cli.sh), so it
 * uses the full DES primitive (with IP/FP) as its Feistel round function and
 * never calls des_ecm / ip() / fp(). This corresponds to the "With unmodified
 * DES" DEAL variant documented in deal.c's own timing table.
 *
 * The 64-bit DES block is carried in a u4byte[2] pair as (high32, low32):
 * word[0] holds bits 1..32 (MSB-first), word[1] holds bits 33..64. The key
 * word[2] pair uses the same big-endian-bit convention. This matches the way
 * deal.c hands key/data words to the round function.
 *
 * This file is emitted verbatim by build_cli.sh because the vendored DEAL-2.zip
 * ships only deal.c + std_defs.h (the DES dependency lived in a sibling des/
 * directory of Gladman's full distribution that is not part of the archive).
 * -------------------------------------------------------------------------- */

#ifndef DES_ROUND_H
#define DES_ROUND_H

/* Initial permutation. */
static const unsigned char IP_TBL[64] = {
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9,  1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7};

/* Final permutation (inverse of IP). */
static const unsigned char FP_TBL[64] = {
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9,  49, 17, 57, 25};

/* Expansion (32 -> 48). */
static const unsigned char E_TBL[48] = {
    32, 1,  2,  3,  4,  5,  4,  5,  6,  7,  8,  9,
    8,  9,  10, 11, 12, 13, 12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1};

/* P permutation (32 -> 32). */
static const unsigned char P_TBL[32] = {
    16, 7,  20, 21, 29, 12, 28, 17, 1,  15, 23, 26, 5,  18, 31, 10,
    2,  8,  24, 14, 32, 27, 3,  9,  19, 13, 30, 6,  22, 11, 4,  25};

/* Permuted choice 1 (64 -> 56). */
static const unsigned char PC1_TBL[56] = {
    57, 49, 41, 33, 25, 17, 9,  1,  58, 50, 42, 34, 26, 18,
    10, 2,  59, 51, 43, 35, 27, 19, 11, 3,  60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15, 7,  62, 54, 46, 38, 30, 22,
    14, 6,  61, 53, 45, 37, 29, 21, 13, 5,  28, 20, 12, 4};

/* Permuted choice 2 (56 -> 48). */
static const unsigned char PC2_TBL[48] = {
    14, 17, 11, 24, 1,  5,  3,  28, 15, 6,  21, 10,
    23, 19, 12, 4,  26, 8,  16, 7,  27, 20, 13, 2,
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32};

/* Per-round left shifts. */
static const unsigned char SHIFT_TBL[16] = {
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1};

/* Eight S-boxes. */
static const unsigned char S_BOX[8][64] = {
    {14, 4,  13, 1,  2,  15, 11, 8,  3,  10, 6,  12, 5,  9,  0,  7,
     0,  15, 7,  4,  14, 2,  13, 1,  10, 6,  12, 11, 9,  5,  3,  8,
     4,  1,  14, 8,  13, 6,  2,  11, 15, 12, 9,  7,  3,  10, 5,  0,
     15, 12, 8,  2,  4,  9,  1,  7,  5,  11, 3,  14, 10, 0,  6,  13},
    {15, 1,  8,  14, 6,  11, 3,  4,  9,  7,  2,  13, 12, 0,  5,  10,
     3,  13, 4,  7,  15, 2,  8,  14, 12, 0,  1,  10, 6,  9,  11, 5,
     0,  14, 7,  11, 10, 4,  13, 1,  5,  8,  12, 6,  9,  3,  2,  15,
     13, 8,  10, 1,  3,  15, 4,  2,  11, 6,  7,  12, 0,  5,  14, 9},
    {10, 0,  9,  14, 6,  3,  15, 5,  1,  13, 12, 7,  11, 4,  2,  8,
     13, 7,  0,  9,  3,  4,  6,  10, 2,  8,  5,  14, 12, 11, 15, 1,
     13, 6,  4,  9,  8,  15, 3,  0,  11, 1,  2,  12, 5,  10, 14, 7,
     1,  10, 13, 0,  6,  9,  8,  7,  4,  15, 14, 3,  11, 5,  2,  12},
    {7,  13, 14, 3,  0,  6,  9,  10, 1,  2,  8,  5,  11, 12, 4,  15,
     13, 8,  11, 5,  6,  15, 0,  3,  4,  7,  2,  12, 1,  10, 14, 9,
     10, 6,  9,  0,  12, 11, 7,  13, 15, 1,  3,  14, 5,  2,  8,  4,
     3,  15, 0,  6,  10, 1,  13, 8,  9,  4,  5,  11, 12, 7,  2,  14},
    {2,  12, 4,  1,  7,  10, 11, 6,  8,  5,  3,  15, 13, 0,  14, 9,
     14, 11, 2,  12, 4,  7,  13, 1,  5,  0,  15, 10, 3,  9,  8,  6,
     4,  2,  1,  11, 10, 13, 7,  8,  15, 9,  12, 5,  6,  3,  0,  14,
     11, 8,  12, 7,  1,  14, 2,  13, 6,  15, 0,  9,  10, 4,  5,  3},
    {12, 1,  10, 15, 9,  2,  6,  8,  0,  13, 3,  4,  14, 7,  5,  11,
     10, 15, 4,  2,  7,  12, 9,  5,  6,  1,  13, 14, 0,  11, 3,  8,
     9,  14, 15, 5,  2,  8,  12, 3,  7,  0,  4,  10, 1,  13, 11, 6,
     4,  3,  2,  12, 9,  5,  15, 10, 11, 14, 1,  7,  6,  0,  8,  13},
    {4,  11, 2,  14, 15, 0,  8,  13, 3,  12, 9,  7,  5,  10, 6,  1,
     13, 0,  11, 7,  4,  9,  1,  10, 14, 3,  5,  12, 2,  15, 8,  6,
     1,  4,  11, 13, 12, 3,  7,  14, 10, 15, 6,  8,  0,  5,  9,  2,
     6,  11, 13, 8,  1,  4,  10, 7,  9,  5,  0,  15, 14, 2,  3,  12},
    {13, 2,  8,  4,  6,  15, 11, 1,  10, 9,  3,  14, 5,  0,  12, 7,
     1,  15, 13, 8,  10, 3,  7,  4,  12, 5,  6,  11, 0,  14, 9,  2,
     7,  11, 4,  1,  9,  12, 14, 2,  0,  6,  10, 13, 15, 3,  5,  8,
     2,  1,  14, 7,  4,  10, 8,  13, 15, 12, 9,  0,  3,  5,  6,  11}};

/* --- bit helpers ------------------------------------------------------- */
/* Bits are numbered MSB-first across the 64-bit block held as (hi, lo). */

static unsigned char des_get_bit(const u4byte blk[2], int pos /* 1-based */) {
  pos -= 1;
  u4byte word = blk[pos >> 5];
  int sh = 31 - (pos & 31);
  return (unsigned char)((word >> sh) & 1u);
}

static void des_permute(const u4byte in[2], u4byte out[2],
                        const unsigned char *tbl, int n) {
  out[0] = out[1] = 0;
  for (int i = 0; i < n; i++) {
    unsigned char bit = des_get_bit(in, tbl[i]);
    int sh = 31 - (i & 31);
    out[i >> 5] |= ((u4byte)bit) << sh;
  }
}

/* 56-bit value held in a single 64-bit-style pair where bit 1 is the MSB of
 * a 56-bit field packed into the low 56 bits of (hi:lo). We instead keep the
 * 28-bit halves C and D as plain ints (bit 1 = MSB) for the key schedule. */

/* des_ky: derive 16 round keys (each 48 bits stored as two u4byte: a 24-bit
 * value in bits 23..0 of ks[2*r] and ks[2*r+1]). 32 words total. */
void des_ky(const u4byte key[2], u4byte ks[32]) {
  /* PC1: 64 -> 56 bits, split into C (28) and D (28). */
  unsigned int C = 0, D = 0;
  for (int i = 0; i < 28; i++) {
    C = (C << 1) | des_get_bit(key, PC1_TBL[i]);
  }
  for (int i = 28; i < 56; i++) {
    D = (D << 1) | des_get_bit(key, PC1_TBL[i]);
  }

  for (int r = 0; r < 16; r++) {
    int s = SHIFT_TBL[r];
    C = ((C << s) | (C >> (28 - s))) & 0x0fffffffu;
    D = ((D << s) | (D >> (28 - s))) & 0x0fffffffu;

    /* Build the 56-bit CD field big-endian in a 2-word array where bit 1
     * (MSB) corresponds to des_get_bit position 1: C occupies positions
     * 1..28, D occupies positions 29..56. */
    u4byte cdblk[2];
    cdblk[0] = (C << 4) | (D >> 24);       /* bits 1..32: C(28) + D[0..3] */
    cdblk[1] = (D & 0x00ffffffu) << 8;     /* bits 33..56: D[4..27]        */

    /* PC2: select 48 bits from the 56-bit cdblk (positions 1..56). */
    u4byte k0 = 0, k1 = 0; /* each holds 24 bits, MSB-first in low 24 bits */
    for (int i = 0; i < 24; i++) {
      k0 = (k0 << 1) | des_get_bit(cdblk, PC2_TBL[i]);
    }
    for (int i = 24; i < 48; i++) {
      k1 = (k1 << 1) | des_get_bit(cdblk, PC2_TBL[i]);
    }
    ks[2 * r] = k0;
    ks[2 * r + 1] = k1;
  }
}

/* The Feistel f-function: expand R (32) to 48, XOR round key, S-box to 32,
 * then P-permute. Round key supplied as two 24-bit halves. */
static u4byte des_f(u4byte R, u4byte k0, u4byte k1) {
  /* Expansion E: build a 48-bit value as two 24-bit halves. */
  u4byte rin[2];
  rin[0] = R; /* treat R as a 32-bit block in word 0; word 1 unused for E */
  rin[1] = 0;
  unsigned int e_hi = 0, e_lo = 0; /* 24 bits each */
  for (int i = 0; i < 24; i++) {
    e_hi = (e_hi << 1) | des_get_bit(rin, E_TBL[i]);
  }
  for (int i = 24; i < 48; i++) {
    e_lo = (e_lo << 1) | des_get_bit(rin, E_TBL[i]);
  }
  e_hi ^= k0;
  e_lo ^= k1;

  /* Combine the 48-bit value into 8 groups of 6 bits and apply S-boxes. */
  unsigned long long e48 = ((unsigned long long)(e_hi & 0x00ffffffu) << 24) |
                           (unsigned long long)(e_lo & 0x00ffffffu);
  u4byte sout = 0;
  for (int b = 0; b < 8; b++) {
    unsigned int six = (unsigned int)((e48 >> (42 - 6 * b)) & 0x3f);
    unsigned int row = ((six & 0x20) >> 4) | (six & 0x01);
    unsigned int col = (six >> 1) & 0x0f;
    sout = (sout << 4) | S_BOX[b][row * 16 + col];
  }

  /* P permutation on the 32-bit sout. */
  u4byte pin[2], pout[2];
  pin[0] = sout;
  pin[1] = 0;
  pout[0] = 0;
  for (int i = 0; i < 32; i++) {
    pout[0] = (pout[0] << 1) | des_get_bit(pin, P_TBL[i]);
  }
  return pout[0];
}

/* des_ec: full single-block DES encryption (with IP and FP). */
void des_ec(const u4byte in[2], u4byte out[2], const u4byte ks[32]) {
  u4byte blk[2], perm[2];
  blk[0] = in[0];
  blk[1] = in[1];

  des_permute(blk, perm, IP_TBL, 64);
  u4byte L = perm[0];
  u4byte R = perm[1];

  for (int r = 0; r < 16; r++) {
    u4byte f = des_f(R, ks[2 * r], ks[2 * r + 1]);
    u4byte tmp = R;
    R = L ^ f;
    L = tmp;
  }

  /* Preoutput is R||L (note the swap). */
  u4byte pre[2];
  pre[0] = R;
  pre[1] = L;
  des_permute(pre, out, FP_TBL, 64);
}

#endif /* DES_ROUND_H */
