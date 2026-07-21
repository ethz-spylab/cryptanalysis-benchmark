#define _POSIX_C_SOURCE 200809L

#include "algorithm.h"
#include "cli_stdin.h"
#include "common.h"
#include <argp.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "feal4 1.0";
static const char doc[] =
    "FEAL-4 CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random 192-bit encryption key\n"
    "  generate_random_plaintext  Generate a random 64-bit plaintext\n"
    "  encrypt                    Encrypt a 64-bit plaintext block\n"
    "  decrypt                    Decrypt a 64-bit ciphertext block\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via --key/--plaintext/--ciphertext flags\n"
    "or via stdin as 'key: value' lines. Use --batch for multiple queries\n"
    "separated by '---' lines.";

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"key", 'k', "HEX", 0,
     "192-bit key as 48 hex characters (for encrypt/decrypt)", 0},
    {"plaintext", 'p', "HEX", 0,
     "64-bit plaintext as 16 hex characters (for encrypt)", 0},
    {"ciphertext", 'c', "HEX", 0,
     "64-bit ciphertext as 16 hex characters (for decrypt)", 0},
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

/* ── Commands ────────────────────────────────────────────────────────── */

static int cmd_generate_secrets(void) {
  uint32_t key[6];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(key, sizeof(uint32_t), 6, urandom);
  fclose(urandom);

  if (bytes_read != 6) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("key: ");
  printf("0x");
  for (int i = 0; i < 6; i++) {
    printf("%08x", key[i]);
  }
  printf("\n");

  return 0;
}

static int cmd_generate_random_plaintext(void) {
  uint64_t plaintext;

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(&plaintext, sizeof(uint64_t), 1, urandom);
  fclose(urandom);

  if (bytes_read != 1) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("plaintext: 0x%016lx\n", plaintext);

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

  uint32_t key[6];
  uint64_t plaintext;

  if (!parse_hex_key_6x32(key_hex, key)) {
    fprintf(
        stderr,
        "Error: Invalid key format. Expected 48 hex characters (192 bits)\n");
    return 1;
  }

  if (!parse_hex_u64(pt_hex, &plaintext)) {
    fprintf(stderr,
            "Error: Invalid plaintext format. Expected 16 hex characters "
            "(64 bits)\n");
    return 1;
  }

  uint64_t ciphertext = encrypt_with_key(plaintext, key);

  printf("ciphertext: 0x%016lx\n", ciphertext);

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

  uint32_t key[6];
  uint64_t ciphertext;

  if (!parse_hex_key_6x32(key_hex, key)) {
    fprintf(
        stderr,
        "Error: Invalid key format. Expected 48 hex characters (192 bits)\n");
    return 1;
  }

  if (!parse_hex_u64(ct_hex, &ciphertext)) {
    fprintf(stderr,
            "Error: Invalid ciphertext format. Expected 16 hex characters "
            "(64 bits)\n");
    return 1;
  }

  uint64_t plaintext = decrypt_with_key(ciphertext, key);

  printf("plaintext: 0x%016lx\n", plaintext);

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
