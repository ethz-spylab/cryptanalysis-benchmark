#define _POSIX_C_SOURCE 200809L

/* Make MSVC types work: unsigned __int64 -> unsigned long long, etc. */
#define __int64 long long
#define __int16 short

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>

extern "C" {
#include "cli_stdin.h"
}
#include <argp.h>

/* Include the S-box lookup tables from the reference implementation */
#include "decryption_4bit.inc"

#define PRESENT_KEYLEN 10   /* 80 bits */
#define PRESENT_BLOCKLEN 8  /* 64 bits */

/* Macros from the reference implementation */
#define high1_64(h1in)     ((uint64_t)(h1in) >> 63)
#define high4_64(h4in)     ((uint64_t)(h4in) >> 60)
#define rotate1l_64(r1lin) (high1_64(r1lin) | ((r1lin) << 1))
#define rotate4l_64(r4lin) (high4_64(r4lin) | ((r4lin) << 4))

/*
 * PRESENT key scheduling (forward direction).
 * Generates 32 subkeys from the 80-bit master key.
 */
static void present_key_schedule(uint64_t keyhigh, uint16_t keylow,
                                  uint64_t subkey[32]) {
  uint64_t temp;
  for (int round = 0; round < 32; round++) {
    subkey[round] = keyhigh;
    temp = keyhigh;
    keyhigh <<= 61;
    keyhigh |= ((uint64_t)keylow << 45);
    keyhigh |= (temp >> 19);
    keylow = (uint16_t)((temp >> 3) & 0xFFFF);

    temp = keyhigh >> 60;
    keyhigh &= 0x0FFFFFFFFFFFFFFFULL;
    temp = sBox4[temp];
    keyhigh |= temp << 60;

    keylow ^= (uint16_t)(((round + 1) & 0x01) << 15);
    keyhigh ^= ((round + 1) >> 1);
  }
}

/*
 * PRESENT encryption.
 * Encrypts a 64-bit block in-place.
 */
static void present_encrypt(uint64_t *state, uint64_t keyhigh,
                             uint16_t keylow) {
  uint64_t subkey[32];
  uint64_t temp;
  uint16_t sBoxValue;

  present_key_schedule(keyhigh, keylow, subkey);

  for (int i = 0; i < 31; i++) {
    /* addRoundkey */
    *state ^= subkey[i];

    /* sBoxLayer */
    for (int sBoxNr = 0; sBoxNr < 16; sBoxNr++) {
      sBoxValue = (uint16_t)(*state & 0xF);
      *state &= 0xFFFFFFFFFFFFFFF0ULL;
      *state |= sBox4[sBoxValue];
      *state = rotate4l_64(*state);
    }

    /* pLayer */
    temp = 0;
    for (int k = 0; k < 64; k++) {
      int position = (16 * k) % 63;
      if (k == 63)
        position = 63;
      temp |= ((*state >> k) & 0x1) << position;
    }
    *state = temp;
  }

  /* addRoundkey (round 31) */
  *state ^= subkey[31];
}

/*
 * PRESENT decryption.
 * Decrypts a 64-bit block in-place.
 */
static void present_decrypt(uint64_t *state, uint64_t keyhigh,
                             uint16_t keylow) {
  uint64_t subkey[32];
  uint64_t temp;
  uint16_t sBoxValue;

  present_key_schedule(keyhigh, keylow, subkey);

  int keyindex = 31;
  for (int i = 0; i < 31; i++) {
    /* addRoundkey */
    *state ^= subkey[keyindex];
    keyindex--;

    /* inverse pLayer */
    temp = 0;
    for (int k = 0; k < 64; k++) {
      int position = (4 * k) % 63;
      if (k == 63)
        position = 63;
      temp |= ((*state >> k) & 0x1) << position;
    }
    *state = temp;

    /* inverse sBoxLayer */
    for (int sBoxNr = 0; sBoxNr < 16; sBoxNr++) {
      sBoxValue = (uint16_t)(*state & 0xF);
      *state &= 0xFFFFFFFFFFFFFFF0ULL;
      *state |= invsBox4[sBoxValue];
      *state = rotate4l_64(*state);
    }
  }

  /* addRoundkey (round 0) */
  *state ^= subkey[0];
}

/* ── CLI boilerplate ─────────────────────────────────────────────── */

const char *argp_program_version = "present-80 1.0";
static const char doc[] =
    "PRESENT-80 CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random 80-bit encryption key\n"
    "  generate_random_plaintext  Generate a random 64-bit plaintext\n"
    "  encrypt                    Encrypt a 64-bit plaintext block\n"
    "  decrypt                    Decrypt a 64-bit ciphertext block\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via --key/--plaintext/--ciphertext flags\n"
    "or via stdin as 'key: value' lines. Use --batch for multiple queries\n"
    "separated by '---' lines.";

static struct argp_option options[] = {
    {(char *)"key", 'k', (char *)"HEX", 0,
     (char *)"80-bit key as 20 hex characters (for encrypt/decrypt)", 0},
    {(char *)"plaintext", 'p', (char *)"HEX", 0,
     (char *)"64-bit plaintext as 16 hex characters (for encrypt)", 0},
    {(char *)"ciphertext", 'c', (char *)"HEX", 0,
     (char *)"64-bit ciphertext as 16 hex characters (for decrypt)", 0},
    {(char *)"batch", 'b', 0, 0,
     (char *)"Read inputs from stdin, one block per query, separated by ---",
     0},
    {(char *)"count", 'n', (char *)"N", 0,
     (char *)"Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *key;
  const char *plaintext;
  const char *ciphertext;
  int batch;
  int count;
};

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
  struct arguments *args = (struct arguments *)state->input;
  switch (key) {
  case 'k':
    args->key = arg;
    break;
  case 'p':
    args->plaintext = arg;
    break;
  case 'c':
    args->ciphertext = arg;
    break;
  case 'b':
    args->batch = 1;
    break;
  case 'n':
    args->count = atoi(arg);
    break;
  case ARGP_KEY_ARG:
    if (state->arg_num == 0)
      args->command = arg;
    else
      argp_error(state, "unexpected positional argument: %s", arg);
    break;
  case ARGP_KEY_END:
    if (!args->command)
      argp_error(state, "missing required argument: CMD");
    break;
  default:
    return ARGP_ERR_UNKNOWN;
  }
  return 0;
}

static struct argp argp_parser = {options, parse_opt, (char *)"CMD", doc, NULL,
                                  NULL, NULL};

static void print_hex(const uint8_t *data, size_t len) {
  printf("0x");
  for (size_t i = 0; i < len; i++) {
    printf("%02x", data[i]);
  }
}

static int parse_hex(const char *hex_str, uint8_t *out, size_t expected_len) {
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X')) {
    hex_str += 2;
  }

  size_t hex_len = strlen(hex_str);
  if (hex_len != expected_len * 2) {
    return -1;
  }

  for (size_t i = 0; i < expected_len; i++) {
    unsigned int byte;
    if (sscanf(hex_str + 2 * i, "%2x", &byte) != 1) {
      return -1;
    }
    out[i] = (uint8_t)byte;
  }

  return 0;
}

/* Convert 10-byte key to keyhigh (8 bytes) + keylow (2 bytes) */
static void key_bytes_to_parts(const uint8_t *key_bytes, uint64_t *keyhigh,
                                uint16_t *keylow) {
  *keyhigh = 0;
  for (int i = 0; i < 8; i++)
    *keyhigh = (*keyhigh << 8) | key_bytes[i];
  *keylow = ((uint16_t)key_bytes[8] << 8) | key_bytes[9];
}

/* Convert 8-byte block to uint64_t (big-endian) */
static uint64_t block_bytes_to_u64(const uint8_t *bytes) {
  uint64_t val = 0;
  for (int i = 0; i < 8; i++)
    val = (val << 8) | bytes[i];
  return val;
}

/* Convert uint64_t to 8-byte block (big-endian) */
static void u64_to_block_bytes(uint64_t val, uint8_t *bytes) {
  for (int i = 7; i >= 0; i--) {
    bytes[i] = (uint8_t)(val & 0xFF);
    val >>= 8;
  }
}

static int cmd_generate_secrets(void) {
  uint8_t key[PRESENT_KEYLEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(key, 1, PRESENT_KEYLEN, urandom);
  fclose(urandom);

  if (bytes_read != PRESENT_KEYLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("key: ");
  print_hex(key, PRESENT_KEYLEN);
  printf("\n");

  return 0;
}

static int cmd_generate_random_plaintext(void) {
  uint8_t plaintext[PRESENT_BLOCKLEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(plaintext, 1, PRESENT_BLOCKLEN, urandom);
  fclose(urandom);

  if (bytes_read != PRESENT_BLOCKLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("plaintext: ");
  print_hex(plaintext, PRESENT_BLOCKLEN);
  printf("\n");

  return 0;
}

static int cmd_encrypt(const char *key_hex, const char *pt_hex) {
  if (!key_hex) {
    fprintf(stderr, "Error: --key is required for the encrypt command\n");
    return 1;
  }
  if (!pt_hex) {
    fprintf(stderr, "Error: --plaintext is required for the encrypt command\n");
    return 1;
  }

  uint8_t key_bytes[PRESENT_KEYLEN];
  uint8_t pt_bytes[PRESENT_BLOCKLEN];
  uint8_t ct_bytes[PRESENT_BLOCKLEN];

  if (parse_hex(key_hex, key_bytes, PRESENT_KEYLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid key format. Expected 20 hex characters (80 bits)\n");
    return 1;
  }

  if (parse_hex(pt_hex, pt_bytes, PRESENT_BLOCKLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid plaintext format. Expected 16 hex characters "
            "(64 bits)\n");
    return 1;
  }

  uint64_t keyhigh;
  uint16_t keylow;
  key_bytes_to_parts(key_bytes, &keyhigh, &keylow);

  uint64_t state = block_bytes_to_u64(pt_bytes);
  present_encrypt(&state, keyhigh, keylow);
  u64_to_block_bytes(state, ct_bytes);

  printf("ciphertext: ");
  print_hex(ct_bytes, PRESENT_BLOCKLEN);
  printf("\n");

  return 0;
}

static int cmd_decrypt(const char *key_hex, const char *ct_hex) {
  if (!key_hex) {
    fprintf(stderr, "Error: --key is required for the decrypt command\n");
    return 1;
  }
  if (!ct_hex) {
    fprintf(stderr,
            "Error: --ciphertext is required for the decrypt command\n");
    return 1;
  }

  uint8_t key_bytes[PRESENT_KEYLEN];
  uint8_t ct_bytes[PRESENT_BLOCKLEN];
  uint8_t pt_bytes[PRESENT_BLOCKLEN];

  if (parse_hex(key_hex, key_bytes, PRESENT_KEYLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid key format. Expected 20 hex characters (80 bits)\n");
    return 1;
  }

  if (parse_hex(ct_hex, ct_bytes, PRESENT_BLOCKLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid ciphertext format. Expected 16 hex characters "
            "(64 bits)\n");
    return 1;
  }

  uint64_t keyhigh;
  uint16_t keylow;
  key_bytes_to_parts(key_bytes, &keyhigh, &keylow);

  uint64_t state = block_bytes_to_u64(ct_bytes);
  present_decrypt(&state, keyhigh, keylow);
  u64_to_block_bytes(state, pt_bytes);

  printf("plaintext: ");
  print_hex(pt_bytes, PRESENT_BLOCKLEN);
  printf("\n");

  return 0;
}

static int cmd_encrypt_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for encrypt\n");
    return 1;
  }
  int rc = cmd_encrypt(stdin_kv_get(&block, "key"),
                       stdin_kv_get(&block, "plaintext"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_decrypt_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for decrypt\n");
    return 1;
  }
  int rc = cmd_decrypt(stdin_kv_get(&block, "key"),
                       stdin_kv_get(&block, "ciphertext"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_encrypt_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = cmd_encrypt(stdin_kv_get(&block, "key"),
                         stdin_kv_get(&block, "plaintext"));
    stdin_kv_free(&block);
    if (rc != 0)
      return rc;
  }
  return 0;
}

static int cmd_decrypt_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = cmd_decrypt(stdin_kv_get(&block, "key"),
                         stdin_kv_get(&block, "ciphertext"));
    stdin_kv_free(&block);
    if (rc != 0)
      return rc;
  }
  return 0;
}

static int cmd_generate_random_plaintext_batch(int count) {
  for (int i = 0; i < count; i++) {
    if (i > 0)
      printf("---\n");
    int rc = cmd_generate_random_plaintext();
    if (rc != 0)
      return rc;
  }
  return 0;
}

int main(int argc, char *argv[]) {
  struct arguments args = {};

  argp_parse(&argp_parser, argc, argv, 0, 0, &args);

  if (strcmp(args.command, "generate_secrets") == 0) {
    return cmd_generate_secrets();
  } else if (strcmp(args.command, "generate_random_plaintext") == 0) {
    if (args.batch)
      return cmd_generate_random_plaintext_batch(args.count > 0 ? args.count
                                                                : 1);
    return cmd_generate_random_plaintext();
  } else if (strcmp(args.command, "encrypt") == 0) {
    if (args.batch)
      return cmd_encrypt_batch();
    if (!args.key && !args.plaintext)
      return cmd_encrypt_stdin();
    return cmd_encrypt(args.key, args.plaintext);
  } else if (strcmp(args.command, "decrypt") == 0) {
    if (args.batch)
      return cmd_decrypt_batch();
    if (!args.key && !args.ciphertext)
      return cmd_decrypt_stdin();
    return cmd_decrypt(args.key, args.ciphertext);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
