#ifndef ALGORITHM_H
#define ALGORITHM_H
#include <stdint.h>
uint64_t encrypt_with_key(uint64_t plain, const uint32_t key[6]);
uint64_t decrypt_with_key(uint64_t cypher, const uint32_t key[6]);
#endif
