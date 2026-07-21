#define _POSIX_C_SOURCE 200809L

#include "ecrypt-sync.h"
#include "cli_stdin.h"
#include <argp.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHACHA_KEYLEN 16   /* 128 bits */
#define CHACHA_IVLEN 8     /* 64 bits */
#define CHACHA_BLOCKLEN 16 /* 16 bytes for CLI plaintext/ciphertext */

const char *argp_program_version = "chacha8-128 1.0";
static const char doc[] =
    "ChaCha8-128 CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random 128-bit encryption key\n"
    "  generate_random_plaintext  Generate a random 128-bit plaintext\n"
    "  encrypt                    Encrypt a 128-bit plaintext block\n"
    "  decrypt                    Decrypt a 128-bit ciphertext block\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Encrypt generates a random IV and outputs both iv and ciphertext.\n"
    "Decrypt requires key, iv, and ciphertext as inputs.";

static struct argp_option options[] = {
    {"key", 'k', "HEX", 0,
     "128-bit key as 32 hex characters", 0},
    {"plaintext", 'p', "HEX", 0,
     "128-bit plaintext as 32 hex characters (for encrypt)", 0},
    {"ciphertext", 'c', "HEX", 0,
     "128-bit ciphertext as 32 hex characters (for decrypt)", 0},
    {"iv", 'i', "HEX", 0,
     "64-bit IV as 16 hex characters (for decrypt)", 0},
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *key;
  const char *plaintext;
  const char *ciphertext;
  const char *iv;
  int batch;
  int count;
};

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
  struct arguments *args = state->input;
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
  case 'i':
    args->iv = arg;
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

static struct argp argp = {options, parse_opt, "CMD", doc, NULL, NULL, NULL};

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

static int cmd_generate_secrets(void) {
  uint8_t key[CHACHA_KEYLEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(key, 1, CHACHA_KEYLEN, urandom);
  fclose(urandom);

  if (bytes_read != CHACHA_KEYLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("key: ");
  print_hex(key, CHACHA_KEYLEN);
  printf("\n");

  return 0;
}

static int cmd_generate_random_plaintext(void) {
  uint8_t plaintext[CHACHA_BLOCKLEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(plaintext, 1, CHACHA_BLOCKLEN, urandom);
  fclose(urandom);

  if (bytes_read != CHACHA_BLOCKLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("plaintext: ");
  print_hex(plaintext, CHACHA_BLOCKLEN);
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

  uint8_t key[CHACHA_KEYLEN];
  uint8_t pt[CHACHA_BLOCKLEN];
  uint8_t ct[CHACHA_BLOCKLEN];
  uint8_t iv[CHACHA_IVLEN];

  if (parse_hex(key_hex, key, CHACHA_KEYLEN) != 0) {
    fprintf(stderr, "Error: Invalid key format. Expected 32 hex characters\n");
    return 1;
  }

  if (parse_hex(pt_hex, pt, CHACHA_BLOCKLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid plaintext format. Expected 32 hex characters\n");
    return 1;
  }

  /* Generate random IV */
  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }
  size_t bytes_read = fread(iv, 1, CHACHA_IVLEN, urandom);
  fclose(urandom);
  if (bytes_read != CHACHA_IVLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  ECRYPT_ctx ctx;
  ECRYPT_keysetup(&ctx, key, 128, 64);
  ECRYPT_ivsetup(&ctx, iv);
  ECRYPT_encrypt_bytes(&ctx, pt, ct, CHACHA_BLOCKLEN);

  printf("iv: ");
  print_hex(iv, CHACHA_IVLEN);
  printf("\n");
  printf("ciphertext: ");
  print_hex(ct, CHACHA_BLOCKLEN);
  printf("\n");

  return 0;
}

static int cmd_decrypt(const char *key_hex, const char *iv_hex,
                       const char *ct_hex) {
  if (!key_hex) {
    fprintf(stderr, "Error: --key is required for the decrypt command\n");
    return 1;
  }
  if (!iv_hex) {
    fprintf(stderr, "Error: --iv is required for the decrypt command\n");
    return 1;
  }
  if (!ct_hex) {
    fprintf(stderr,
            "Error: --ciphertext is required for the decrypt command\n");
    return 1;
  }

  uint8_t key[CHACHA_KEYLEN];
  uint8_t iv[CHACHA_IVLEN];
  uint8_t ct[CHACHA_BLOCKLEN];
  uint8_t pt[CHACHA_BLOCKLEN];

  if (parse_hex(key_hex, key, CHACHA_KEYLEN) != 0) {
    fprintf(stderr, "Error: Invalid key format. Expected 32 hex characters\n");
    return 1;
  }

  if (parse_hex(iv_hex, iv, CHACHA_IVLEN) != 0) {
    fprintf(stderr, "Error: Invalid IV format. Expected 16 hex characters\n");
    return 1;
  }

  if (parse_hex(ct_hex, ct, CHACHA_BLOCKLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid ciphertext format. Expected 32 hex characters\n");
    return 1;
  }

  ECRYPT_ctx ctx;
  ECRYPT_keysetup(&ctx, key, 128, 64);
  ECRYPT_ivsetup(&ctx, iv);
  ECRYPT_decrypt_bytes(&ctx, ct, pt, CHACHA_BLOCKLEN);

  printf("plaintext: ");
  print_hex(pt, CHACHA_BLOCKLEN);
  printf("\n");

  return 0;
}

/* Stdin / Batch wrappers */

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
                       stdin_kv_get(&block, "iv"),
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
                         stdin_kv_get(&block, "iv"),
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
  struct arguments args = {0};

  ECRYPT_init();

  argp_parse(&argp, argc, argv, 0, 0, &args);

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
    if (!args.key && !args.iv && !args.ciphertext)
      return cmd_decrypt_stdin();
    return cmd_decrypt(args.key, args.iv, args.ciphertext);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
