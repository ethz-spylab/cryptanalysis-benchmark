#define _POSIX_C_SOURCE 200809L
#include "common.h"
#include <ctype.h>
#include <string.h>
static int hexval(int ch) {
  if (ch >= '0' && ch <= '9')
    return ch - '0';
  if (ch >= 'a' && ch <= 'f')
    return 10 + ch - 'a';
  if (ch >= 'A' && ch <= 'F')
    return 10 + ch - 'A';
  return -1;
}
static void strip_prefix(const char **ps) {
  const char *s = *ps;
  while (isspace((unsigned char)*s))
    s++;
  if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
    s += 2;
  *ps = s;
}
bool parse_hex_u64(const char *s, uint64_t *out) {
  strip_prefix(&s);
  uint64_t v = 0;
  int n = 0;
  for (; *s; s++) {
    if (isspace((unsigned char)*s))
      break;
    int hv = hexval(*s);
    if (hv < 0)
      return false;
    if (n >= 16)
      return false;
    v = (v << 4) | (uint64_t)hv;
    n++;
  }
  if (n == 0)
    return false;
  *out = v;
  return true;
}
bool parse_hex_key_6x32(const char *s, uint32_t key[6]) {
  strip_prefix(&s);
  char buf[64] = {0};
  size_t j = 0;
  for (; *s && j < 48; s++) {
    int hv = hexval(*s);
    if (hv < 0) {
      if (isspace((unsigned char)*s))
        continue;
      else
        break;
    }
    buf[j++] = (char)*s;
  }
  if (j != 48)
    return false;
  for (int i = 0; i < 6; i++) {
    uint32_t v = 0;
    for (int k = 0; k < 8; k++) {
      int idx = i * 8 + k;
      int hv = hexval(buf[idx]);
      v = (v << 4) | (uint32_t)hv;
    }
    key[i] = v;
  }
  return true;
}
