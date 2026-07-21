#include "algorithm.h"
#include <stdint.h>

uint8_t rotl2(uint8_t a) {
    return (uint8_t)((uint8_t)(a << 2) | (uint8_t)(a >> 6));
}

uint32_t leftHalf(uint64_t a)  { return (uint32_t)(a >> 32); }
uint32_t rightHalf(uint64_t a) { return (uint32_t)(a & 0xFFFFFFFFu); }

uint8_t sepByte(uint32_t a, uint8_t index) {
    return (uint8_t)((a >> (8u * index)) & 0xFFu);
}

uint32_t combineBytes(uint8_t b3, uint8_t b2, uint8_t b1, uint8_t b0) {
    return ((uint32_t)b3 << 24) | ((uint32_t)b2 << 16) | ((uint32_t)b1 << 8) | (uint32_t)b0;
}

uint64_t combineHalves(uint32_t left, uint32_t right) {
    return ((uint64_t)left << 32) | (uint64_t)right;
}

uint8_t gBox(uint8_t a, uint8_t b, uint8_t mode) {
    // (a + b + mode) mod 256, then rotate left by 2
    uint8_t s = (uint8_t)(a + b + mode);
    return rotl2(s);
}

uint32_t fBox(uint32_t plain) {
    uint8_t x0 = sepByte(plain, 0);
    uint8_t x1 = sepByte(plain, 1);
    uint8_t x2 = sepByte(plain, 2);
    uint8_t x3 = sepByte(plain, 3);

    uint8_t t0 = (uint8_t)(x2 ^ x3);
    uint8_t y1 = gBox((uint8_t)(x0 ^ x1), t0, 1);
    uint8_t y0 = gBox(x0, y1, 0);
    uint8_t y2 = gBox(t0, y1, 0);
    uint8_t y3 = gBox(x3, y2, 1);

    return combineBytes(y3, y2, y1, y0);
}

uint64_t encrypt_with_key(uint64_t plain, const uint32_t key[6]) {

    uint32_t left  = leftHalf(plain);
    uint32_t right = rightHalf(plain);

    left  ^= key[4];
    right ^= key[5];

    uint32_t round2Left  = left ^ right;
    uint32_t round2Right = left ^ fBox(round2Left ^ key[0]);

    uint32_t round3Left  = round2Right;
    uint32_t round3Right = round2Left ^ fBox(round2Right ^ key[1]);

    uint32_t round4Left  = round3Right;
    uint32_t round4Right = round3Left ^ fBox(round3Right ^ key[2]);

    uint32_t cipherLeft  = round4Left ^ fBox(round4Right ^ key[3]);
    uint32_t cipherRight = cipherLeft ^ round4Right;

    return combineHalves(cipherLeft, cipherRight);
}

uint64_t decrypt_with_key(uint64_t cipher, const uint32_t key[6]) {
    uint32_t left  = leftHalf(cipher);
    uint32_t right = rightHalf(cipher);

    uint32_t round4Right = left ^ right;
    uint32_t round4Left = left ^ fBox(round4Right ^ key[3]);

    uint32_t round3Right = round4Left;
    uint32_t round3Left = round4Right ^ fBox(round3Right ^ key[2]);

    uint32_t round2Right = round3Left;
    uint32_t round2Left = round3Right ^ fBox(round2Right ^ key[1]);

    uint32_t round1Right = round2Left;
    uint32_t round1Left = round2Right ^ fBox(round1Right ^ key[0]);

    uint32_t plainLeft = round1Left ^ key[4];
    uint32_t plainRight = round1Right ^ round1Left ^ key[5];

    return combineHalves(plainLeft, plainRight);
}
