#!/bin/bash

# =============================================================================
# solve.sh - RaCoSS Signature Forgery Solution
# =============================================================================
# This script prepares the environment and creates attack.sh for the
# SignatureForgeryGame. The attack exploits the algebraic structure of RaCoSS
# to forge signatures without knowledge of the private key.
#
# Steps:
#   1. Extract the H matrix from the reference implementation (hprint)
#   2. Compute the inverse of H over GF(2) using Sage (invert.sage -> Hinv.c)
#   3. Compile the forgery tool (forge_attack.c)
#   4. Write attack.sh to interact with the game controller
# =============================================================================

set -e

# --- Step 1: Compile hprint to extract the H matrix from sign_tab.h ---------

cat <<'EOF' > /app/hprint.c
#include <stdio.h>
#include "sign_tab.h"

int main()
{
  int i, j;
  printf("H=[\n");
  for (i = 0; i < RACOSS_N_K; ++i) {
    printf("  [");
    for (j = 0; j < RACOSS_N; ++j)
      printf("%d,", RACOSS_H[i][j]);
    printf("],\n");
  }
  printf("]\n");
  return 0;
}
EOF

gcc -I /app/algorithm_src -Wall -o /app/hprint /app/hprint.c
/app/hprint > /app/h.py

# --- Step 2: Compute Hinv.c using Sage --------------------------------------

cat <<'EOF' > /app/invert.sage
import h

Hrows = len(h.H)
Hcols = len(h.H[0])

positions = range(Hrows)

Hselect = matrix(GF(2), h.H).matrix_from_columns(positions)
Hinv = 1 / Hselect

for i in range(Hrows):
    print('{%s},' % ','.join(str(Hinv[i, j]) for j in range(Hrows)))
EOF

cd /app && sage invert.sage > /app/Hinv.c

# --- Step 3: Write and compile the forge attack tool -------------------------

cat <<'EOF' > /app/forge_attack.c
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "api.h"
#include "rng.h"
#include "sha3.h"
#include "sign.h"
#include "sign_tab.h"

extern double byteTo01(unsigned char *);
extern double getRho(unsigned int, double, double);
extern void wrhf(unsigned char *, unsigned char *, int, int, unsigned int);

static const unsigned char Hinv[RACOSS_N_K][RACOSS_N_K] = {
#include "Hinv.c"
};

static int crypto_sign_forge(
  unsigned char *sm,
  unsigned long long *smlen,
  const unsigned char *m,
  unsigned long long mlen,
  const unsigned char *pk
)
{
  double rho = getRho(RACOSS_N, RACOSS_OMEGA, RACOSS_GAMMA);
  unsigned char rbyte[RACOSS_N * 2];
  unsigned char T[RACOSS_N_K][RACOSS_N];
  unsigned char c[RACOSS_N];
  unsigned char z[RACOSS_N];
  unsigned char y[RACOSS_N];
  unsigned char v[RACOSS_N_K];
  unsigned char target[RACOSS_N_K];
  unsigned char *b;
  int blen, pos, i, j, w;

  randombytes(rbyte, RACOSS_N * 2);
  for (i = 0; i < RACOSS_N; ++i) {
    int f = (int)(byteTo01(rbyte + (i * 2)) * 1000);
    y[i] = (f < 1000 * rho);
  }
  for (i = 0; i < RACOSS_N_K; ++i) {
    v[i] = 0;
    for (j = 0; j < RACOSS_N; ++j)
      v[i] ^= RACOSS_H[i][j] & y[j];
  }

  blen = ((RACOSS_N_K + 7) / 8) + (int)mlen + ((RACOSS_N_K * RACOSS_N) / 8);
  b = (unsigned char *)calloc(1, blen);
  pos = 0;

  for (i = 0; i < RACOSS_N_K; ++i) {
    b[pos / 8] ^= v[i] << ((7 - pos) & 7);
    ++pos;
  }
  while (pos & 7) ++pos;
  memcpy(b + pos / 8, m, mlen);
  pos += mlen * 8;

  for (i = 0; i < RACOSS_N_K; ++i) {
    for (j = 0; j < RACOSS_N; ++j) {
      b[pos / 8] ^= RACOSS_H[i][j] << ((7 - pos) & 7);
      ++pos;
    }
    while (pos & 7) ++pos;
  }

  w = (int)(RACOSS_GAMMA * RACOSS_OMEGA);
  wrhf(c, b, blen, w, RACOSS_N);
  free(b);

  pos = 0;
  for (i = 0; i < RACOSS_N_K; ++i)
    for (j = 0; j < RACOSS_N; ++j) {
      T[i][j] = (pk[pos / 8] >> (7 - (pos & 7))) & 1;
      ++pos;
    }

  for (i = 0; i < RACOSS_N_K; ++i) target[i] = v[i];
  for (i = 0; i < RACOSS_N_K; ++i)
    for (j = 0; j < RACOSS_N; ++j)
      target[i] ^= T[i][j] & c[j];

  for (i = 0; i < RACOSS_N; ++i) z[i] = 0;
  for (i = 0; i < RACOSS_N_K; ++i)
    for (j = 0; j < RACOSS_N_K; ++j)
      z[i] ^= Hinv[i][j] & target[j];

  *smlen = mlen + (RACOSS_N / 8) + (RACOSS_N / 8);
  memset(sm, 0, *smlen);

  memcpy(sm, m, mlen);
  pos = mlen * 8;
  for (i = 0; i < RACOSS_N; ++i) {
    sm[pos / 8] ^= z[i] << ((7 - pos) & 7);
    ++pos;
  }
  while (pos & 7) ++pos;
  for (i = 0; i < RACOSS_N; ++i) {
    sm[pos / 8] ^= c[i] << ((7 - pos) & 7);
    ++pos;
  }

  return 0;
}

static void print_hex(const unsigned char *data, size_t len) {
  printf("0x");
  for (size_t i = 0; i < len; i++)
    printf("%02x", data[i]);
}

static int parse_hex(const char *hex_str, unsigned char *out, size_t max_len) {
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X'))
    hex_str += 2;
  size_t hex_len = strlen(hex_str);
  if (hex_len % 2 != 0) return -1;
  size_t byte_len = hex_len / 2;
  if (byte_len > max_len) return -1;
  for (size_t i = 0; i < byte_len; i++) {
    unsigned int byte_val;
    if (sscanf(hex_str + 2 * i, "%2x", &byte_val) != 1) return -1;
    out[i] = (unsigned char)byte_val;
  }
  return (int)byte_len;
}

#define MESSAGE_LEN 33

int main(void)
{
  /* Read public key hex from stdin (too large for argv) */
  char *pk_hex = NULL;
  size_t pk_hex_cap = 0;
  ssize_t pk_hex_len = getline(&pk_hex, &pk_hex_cap, stdin);
  if (pk_hex_len <= 0) {
    fprintf(stderr, "Error: Failed to read public key from stdin\n");
    return 1;
  }
  /* Strip trailing newline */
  while (pk_hex_len > 0 && (pk_hex[pk_hex_len - 1] == '\n' || pk_hex[pk_hex_len - 1] == '\r'))
    pk_hex[--pk_hex_len] = '\0';

  /* Initialize RNG from /dev/urandom */
  unsigned char entropy_input[48];
  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n", strerror(errno));
    free(pk_hex);
    return 1;
  }
  if (fread(entropy_input, 1, 48, urandom) != 48) {
    fprintf(stderr, "Error: Failed to read random bytes\n");
    fclose(urandom);
    free(pk_hex);
    return 1;
  }
  fclose(urandom);
  randombytes_init(entropy_input, NULL, 256);

  /* Parse public key */
  unsigned char pk[CRYPTO_PUBLICKEYBYTES];
  int pk_len = parse_hex(pk_hex, pk, CRYPTO_PUBLICKEYBYTES);
  free(pk_hex);
  if (pk_len != CRYPTO_PUBLICKEYBYTES) {
    fprintf(stderr, "Error: Invalid public key (expected %d bytes, got %d)\n",
            CRYPTO_PUBLICKEYBYTES, pk_len);
    return 1;
  }

  /* Generate random message */
  unsigned char m[MESSAGE_LEN];
  randombytes(m, MESSAGE_LEN);

  /* Forge signature */
  unsigned char sm[MESSAGE_LEN + CRYPTO_BYTES];
  unsigned long long smlen;
  int ret = crypto_sign_forge(sm, &smlen, m, (unsigned long long)MESSAGE_LEN, pk);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_sign_forge failed with code %d\n", ret);
    return 1;
  }

  /* Output message and signature as hex */
  printf("message: ");
  print_hex(m, MESSAGE_LEN);
  printf("\n");

  printf("signature: ");
  print_hex(sm + MESSAGE_LEN, CRYPTO_BYTES);
  printf("\n");

  return 0;
}
EOF

gcc -I /app/algorithm_src -O3 -o /app/forge_attack \
  /app/forge_attack.c \
  /app/algorithm_src/rng.c /app/algorithm_src/sha3.c /app/algorithm_src/sign.c \
  -lcrypto

# --- Step 4: Write the attack script ----------------------------------------

cat <<'ATTACK_EOF' > /app/attack.sh
#!/bin/bash
SERVER_URL="http://game_controller:8000"

# Stage 0: Get the public key
echo "Stage 0: Getting public key..."
response=$(curl -s -X POST "$SERVER_URL/execute_current_stage" \
  -H "Content-Type: application/json" \
  -d '{"stage_payload": {}}')
echo "Stage 0 response: $response"

public_key=$(echo "$response" | python3 -c "import sys, json; print(json.loads(sys.stdin.read())['stage_result']['public key'])")
echo "Public key: ${public_key:0:80}..."

# Forge a signature for a random message (no oracle calls needed)
echo "Forging signature..."
forge_output=$(echo "$public_key" | /app/forge_attack)
echo "$forge_output"

message=$(echo "$forge_output" | grep "^message:" | awk '{print $2}')
signature=$(echo "$forge_output" | grep "^signature:" | awk '{print $2}')

# Stage 1: Submit the forged message and signature
echo "Stage 1: Submitting forged signature..."
response=$(curl -s -X POST "$SERVER_URL/execute_current_stage" \
  -H "Content-Type: application/json" \
  -d "{\"stage_payload\": {\"message\": \"$message\", \"signature\": \"$signature\"}}")
echo "Stage 1 response: $response"

game_won=$(echo "$response" | python3 -c "import sys, json; print(json.loads(sys.stdin.read())['stage_result']['Game won'])")
if [ "$game_won" = "Yes" ]; then
  echo "SUCCESS: Signature forgery successful!"
else
  echo "FAILURE: Signature forgery failed!"
fi
ATTACK_EOF
chmod +x /app/attack.sh

# --- Step 5: Write the security game choice ----------------------------------

echo "SignatureForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
