#ifndef ECRYPT_PORTABLE_H
#define ECRYPT_PORTABLE_H

#include <stdint.h>

typedef uint8_t u8;
typedef uint32_t u32;

#define U8V(v) ((u8)(v) & 0xFFU)
#define U32V(v) ((u32)(v) & 0xFFFFFFFFU)

#define ROTL32(v, n) (U32V((v) << (n)) | ((v) >> (32 - (n))))

#define U8TO32_LITTLE(p) \
  (((u32)(p)[0]) | ((u32)(p)[1] << 8) | \
   ((u32)(p)[2] << 16) | ((u32)(p)[3] << 24))

#define U32TO8_LITTLE(p, v) do { \
  (p)[0] = U8V((v));        \
  (p)[1] = U8V((v) >> 8);   \
  (p)[2] = U8V((v) >> 16);  \
  (p)[3] = U8V((v) >> 24);  \
} while(0)

#endif
