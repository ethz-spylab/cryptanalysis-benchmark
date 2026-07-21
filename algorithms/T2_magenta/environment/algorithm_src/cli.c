#define _POSIX_C_SOURCE 200809L

#include "std_defs.h"
#include "cli_stdin.h"
#include <argp.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAGENTA_KEYLEN 16   /* 128-bit key */
#define MAGENTA_BLOCKLEN 16 /* 128-bit block */
#define MAGENTA_KEYBITS 128

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "magenta-128 1.0";
static const char doc[] =
    "MAGENTA CLI Tool (128-bit key)\v"
    "Commands:\n"
    "  generate_secrets           Generate a random 128-bit encryption key\n"
    "  generate_random_plaintext  Generate a random 128-bit plaintext\n"
    "  encrypt                    Encrypt a 128-bit plaintext block\n"
    "  decrypt                    Decrypt a 128-bit ciphertext block\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via --key/--plaintext/--ciphertext flags\n"
    "or via stdin as 'key: value' lines. Use --batch for multiple queries\n"
    "separated by '---' lines.";

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"key", 'k', "HEX", 0,
     "128-bit key as 32 hex characters (for encrypt/decrypt)", 0},
    {"plaintext", 'p', "HEX", 0,
     "128-bit plaintext as 32 hex characters (for encrypt)", 0},
    {"ciphertext", 'c', "HEX", 0,
     "128-bit ciphertext as 32 hex characters (for decrypt)", 0},
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
  int batch;
  int count;
};

/* ── argp parser ─────────────────────────────────────────────────────── */

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

/* ── Helpers ─────────────────────────────────────────────────────────── */

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

/* ── Commands ────────────────────────────────────────────────────────── */

static int cmd_generate_secrets(void) {
  uint8_t key[MAGENTA_KEYLEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(key, 1, MAGENTA_KEYLEN, urandom);
  fclose(urandom);

  if (bytes_read != MAGENTA_KEYLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("key: ");
  print_hex(key, MAGENTA_KEYLEN);
  printf("\n");

  return 0;
}

static int cmd_generate_random_plaintext(void) {
  uint8_t plaintext[MAGENTA_BLOCKLEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(plaintext, 1, MAGENTA_BLOCKLEN, urandom);
  fclose(urandom);

  if (bytes_read != MAGENTA_BLOCKLEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("plaintext: ");
  print_hex(plaintext, MAGENTA_BLOCKLEN);
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

  uint8_t key[MAGENTA_KEYLEN];
  uint8_t buf[MAGENTA_BLOCKLEN];
  u4byte key_words[MAGENTA_KEYLEN / 4];
  u4byte in_blk[MAGENTA_BLOCKLEN / 4];
  u4byte out_blk[MAGENTA_BLOCKLEN / 4];

  if (parse_hex(key_hex, key, MAGENTA_KEYLEN) != 0) {
    fprintf(
        stderr,
        "Error: Invalid key format. Expected 32 hex characters (128 bits)\n");
    return 1;
  }

  if (parse_hex(pt_hex, buf, MAGENTA_BLOCKLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid plaintext format. Expected 32 hex characters "
            "(128 bits)\n");
    return 1;
  }

  memcpy(key_words, key, MAGENTA_KEYLEN);
  memcpy(in_blk, buf, MAGENTA_BLOCKLEN);

  set_key(key_words, MAGENTA_KEYBITS);
  encrypt(in_blk, out_blk);

  memcpy(buf, out_blk, MAGENTA_BLOCKLEN);

  printf("ciphertext: ");
  print_hex(buf, MAGENTA_BLOCKLEN);
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

  uint8_t key[MAGENTA_KEYLEN];
  uint8_t buf[MAGENTA_BLOCKLEN];
  u4byte key_words[MAGENTA_KEYLEN / 4];
  u4byte in_blk[MAGENTA_BLOCKLEN / 4];
  u4byte out_blk[MAGENTA_BLOCKLEN / 4];

  if (parse_hex(key_hex, key, MAGENTA_KEYLEN) != 0) {
    fprintf(
        stderr,
        "Error: Invalid key format. Expected 32 hex characters (128 bits)\n");
    return 1;
  }

  if (parse_hex(ct_hex, buf, MAGENTA_BLOCKLEN) != 0) {
    fprintf(stderr,
            "Error: Invalid ciphertext format. Expected 32 hex characters "
            "(128 bits)\n");
    return 1;
  }

  memcpy(key_words, key, MAGENTA_KEYLEN);
  memcpy(in_blk, buf, MAGENTA_BLOCKLEN);

  set_key(key_words, MAGENTA_KEYBITS);
  decrypt(in_blk, out_blk);

  memcpy(buf, out_blk, MAGENTA_BLOCKLEN);

  printf("plaintext: ");
  print_hex(buf, MAGENTA_BLOCKLEN);
  printf("\n");

  return 0;
}

/* ── Stdin / Batch wrappers ──────────────────────────────────────────── */

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

/* ── main ────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
  struct arguments args = {0};

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
    if (!args.key && !args.ciphertext)
      return cmd_decrypt_stdin();
    return cmd_decrypt(args.key, args.ciphertext);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
