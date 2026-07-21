#ifndef KATAN_H
#define KATAN_H

#ifndef U64
#define U64
typedef unsigned long long u64;
#endif

#define KATAN_KEYLEN 10   /* 80 bits */
#define KATAN_BLOCKLEN 4  /* 32 bits */
#define KATAN_ROUNDS 254

void katan32_encrypt(const u64 plain[32], u64 cipher[32], const u64 key[80], int rounds);
void katan32_decrypt(const u64 cipher[32], u64 plain[32], const u64 key[80], int rounds);

#endif
