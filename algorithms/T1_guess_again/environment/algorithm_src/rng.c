#include "rng.h"
#include <stdio.h>

int randombytes(unsigned char *x, unsigned long long xlen) {
  FILE *f = fopen("/dev/urandom", "rb");
  if (!f) {
    return -1;
  }

  size_t read = fread(x, 1, (size_t)xlen, f);
  fclose(f);

  if (read != (size_t)xlen) {
    return -1;
  }

  return 0;
}
