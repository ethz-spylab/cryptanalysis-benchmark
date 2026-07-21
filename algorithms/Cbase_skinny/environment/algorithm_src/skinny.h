#ifndef SKINNY_H
#define SKINNY_H

#define SKINNY_VER 0       /* Skinny-64-64 */
#define SKINNY_KEYLEN 8    /* 64 bits */
#define SKINNY_BLOCKLEN 8  /* 64 bits */

void enc(unsigned char* input, const unsigned char* userkey, int ver);
void dec(unsigned char* input, const unsigned char* userkey, int ver);

#endif
