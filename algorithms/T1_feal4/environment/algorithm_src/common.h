#ifndef COMMON_H
#define COMMON_H
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <inttypes.h>
bool parse_hex_u64(const char *s, uint64_t *out);
bool parse_hex_key_6x32(const char *s, uint32_t key[6]);
void print_hex_u64(uint64_t x);
#endif
