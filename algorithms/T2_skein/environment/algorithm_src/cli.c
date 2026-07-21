#define _POSIX_C_SOURCE 200809L

#include "cli_stdin.h"
#include <argp.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Forward declarations for the NIST SHA-3 API ─────────────────────
 *    The actual header is provided via the compiler's -include flag,
 *    so cli.c does not need to know which algorithm it is built with.
 *    These declarations are provided here as a fallback / documentation.
 * ──────────────────────────────────────────────────────────────────── */

#ifndef HASH_API_ALREADY_INCLUDED
typedef unsigned char BitSequence;
typedef unsigned long long DataLength;
typedef enum { SUCCESS = 0, FAIL = 1, BAD_HASHBITLEN = 2 } HashReturn;
extern HashReturn Hash(int hashbitlen, const BitSequence *data,
                       DataLength databitlen, BitSequence *hashval);
#endif

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "sha3-candidate 1.0";
static const char doc[] =
    "Generic SHA-3 candidate CLI Tool\v"
    "Commands:\n"
    "  hash                       Hash a hex-encoded plaintext\n"
    "  generate_secrets           No-op (hash functions have no secrets)\n"
    "  generate_random_plaintext  Generate a random plaintext\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via --plaintext/--hashbitlen flags\n"
    "or via stdin as 'key: value' lines. Use --batch for multiple queries\n"
    "separated by '---' lines.";

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"plaintext", 'p', "HEX", 0, "Plaintext as hex characters (for hash)", 0},
    {"hashbitlen", 'l', "N", 0,
     "Hash output length in bits (default: 256)", 0},
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *plaintext;
  int hashbitlen;
  int batch;
  int count;
};

/* ── argp parser ─────────────────────────────────────────────────────── */

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
  struct arguments *args = state->input;
  switch (key) {
  case 'p':
    args->plaintext = arg;
    break;
  case 'l':
    args->hashbitlen = atoi(arg);
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

static int parse_hex(const char *hex_str, uint8_t *out, size_t *out_len,
                     size_t max_len) {
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X')) {
    hex_str += 2;
  }

  size_t hex_len = strlen(hex_str);
  if (hex_len % 2 != 0) {
    return -1;
  }

  size_t byte_len = hex_len / 2;
  if (byte_len > max_len) {
    return -1;
  }

  for (size_t i = 0; i < byte_len; i++) {
    unsigned int byte;
    if (sscanf(hex_str + 2 * i, "%2x", &byte) != 1) {
      return -1;
    }
    out[i] = (uint8_t)byte;
  }

  *out_len = byte_len;
  return 0;
}

/* ── Commands ────────────────────────────────────────────────────────── */

#define MAX_MESSAGE_LEN (1024 * 1024) /* 1 MiB max message */

static int cmd_hash(const char *msg_hex, int hashbitlen) {
  if (!msg_hex) {
    fprintf(stderr, "Error: --plaintext is required for the hash command\n");
    return 1;
  }

  if (hashbitlen <= 0 || hashbitlen % 8 != 0) {
    fprintf(stderr,
            "Error: --hashbitlen must be a positive multiple of 8\n");
    return 1;
  }

  uint8_t *msg = malloc(MAX_MESSAGE_LEN);
  if (!msg) {
    fprintf(stderr, "Error: Failed to allocate message buffer\n");
    return 1;
  }

  size_t msg_len = 0;
  if (parse_hex(msg_hex, msg, &msg_len, MAX_MESSAGE_LEN) != 0) {
    fprintf(stderr, "Error: Invalid plaintext hex format\n");
    free(msg);
    return 1;
  }

  size_t hash_len = (size_t)hashbitlen / 8;
  uint8_t *hashval = malloc(hash_len);
  if (!hashval) {
    fprintf(stderr, "Error: Failed to allocate hash output buffer\n");
    free(msg);
    return 1;
  }

  DataLength databitlen = (DataLength)msg_len * 8;
  HashReturn ret = Hash(hashbitlen, (const BitSequence *)msg, databitlen,
                        (BitSequence *)hashval);

  free(msg);

  if (ret != SUCCESS) {
    fprintf(stderr, "Error: Hash function failed (code %d)\n", ret);
    free(hashval);
    return 1;
  }

  printf("hash: ");
  print_hex(hashval, hash_len);
  printf("\n");

  free(hashval);
  return 0;
}

static int cmd_generate_random_plaintext(int byte_len) {
  if (byte_len <= 0) {
    byte_len = 32; /* default 32 bytes */
  }

  uint8_t *msg = malloc((size_t)byte_len);
  if (!msg) {
    fprintf(stderr, "Error: Failed to allocate message buffer\n");
    return 1;
  }

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    free(msg);
    return 1;
  }

  size_t bytes_read = fread(msg, 1, (size_t)byte_len, urandom);
  fclose(urandom);

  if (bytes_read != (size_t)byte_len) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    free(msg);
    return 1;
  }

  printf("plaintext: ");
  print_hex(msg, (size_t)byte_len);
  printf("\n");

  free(msg);
  return 0;
}

/* ── Stdin / Batch wrappers ──────────────────────────────────────────── */

static int cmd_hash_stdin(int hashbitlen) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for hash\n");
    return 1;
  }
  const char *hbl = stdin_kv_get(&block, "hashbitlen");
  if (hbl)
    hashbitlen = atoi(hbl);
  int rc = cmd_hash(stdin_kv_get(&block, "plaintext"), hashbitlen);
  stdin_kv_free(&block);
  return rc;
}

static int cmd_hash_batch(int hashbitlen) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    const char *hbl = stdin_kv_get(&block, "hashbitlen");
    int effective_hbl = hbl ? atoi(hbl) : hashbitlen;
    int rc = cmd_hash(stdin_kv_get(&block, "plaintext"), effective_hbl);
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
    int rc = cmd_generate_random_plaintext(32);
    if (rc != 0)
      return rc;
  }
  return 0;
}

/* ── main ────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
  struct arguments args = {0};
  args.hashbitlen = 256; /* default */

  argp_parse(&argp, argc, argv, 0, 0, &args);

  if (strcmp(args.command, "generate_secrets") == 0) {
    return 0;
  } else if (strcmp(args.command, "hash") == 0) {
    if (args.batch)
      return cmd_hash_batch(args.hashbitlen);
    if (!args.plaintext)
      return cmd_hash_stdin(args.hashbitlen);
    return cmd_hash(args.plaintext, args.hashbitlen);
  } else if (strcmp(args.command, "generate_random_plaintext") == 0) {
    if (args.batch)
      return cmd_generate_random_plaintext_batch(args.count > 0 ? args.count
                                                                : 1);
    return cmd_generate_random_plaintext(32);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
