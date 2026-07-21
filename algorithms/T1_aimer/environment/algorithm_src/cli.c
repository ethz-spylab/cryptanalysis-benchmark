#define _POSIX_C_SOURCE 200809L

#include "aim2.h"
#include "cli_stdin.h"
#include <argp.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * AIMer v2.1 / AIM2-128 (parameter set aimer-128s) CLI.
 *
 * AIM2 is the one-way function underlying AIMer's key generation:
 *   aim2(ct = c, pt = p, iv)   with c = AIM2(p, iv)
 * (see aim2.c; the public key is (c, iv), the private key is the preimage p).
 * For the 128-bit parameter set every value is AIM2_NUM_BYTES_FIELD = 16 bytes.
 *
 * This binary exposes that relation as a `hash` oracle so the
 * HashPlaintextRecoveryWithPlaintextReuseAndIVGame can treat:
 *   hidden plaintext x  ==  preimage p
 *   adversary iv        ==  AIM2 initialization vector
 *   hash(x, iv)         ==  c = AIM2(p, iv)
 *
 * Byte convention: the on-the-wire hex string is the raw aim2() buffer in
 * natural order (byte 0 first) -- identical to the upstream/cryptolu
 * simple_keypairs.c convention. generate_random_plaintext, hash input and
 * hash output all use the same convention, so the round trip is internally
 * consistent regardless of the field's internal endianness.
 */

/* AIM2-128: preimage p, initial vector iv and ciphertext c are each
 * AIM2_NUM_BYTES_FIELD (= 16) bytes. */
#define AIM_BLOCK AIM2_NUM_BYTES_FIELD

const char *argp_program_version = "aimer-128s (AIMer v2.1 / AIM2) 1.0";
static const char doc[] =
    "AIMer v2.1 / AIM2-128 one-way-function CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           No-op for this hash task (prints nothing)\n"
    "  generate_random_plaintext  Generate a random 128-bit plaintext\n"
    "  hash                       Compute c = aim2(plaintext, iv) (AIM2-128)\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "hash reads 'plaintext: 0x..' (required, 16 bytes) and optionally\n"
    "'iv: 0x..' (16 bytes) from stdin; if iv is omitted a random 16-byte\n"
    "iv is generated. It prints both 'iv: 0x..' and 'hash: 0x..'.\n"
    "Use --batch for multiple queries separated by '---' lines.";

static struct argp_option options[] = {
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  int batch;
  int count;
};

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
  struct arguments *args = state->input;
  switch (key) {
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
  for (size_t i = 0; i < len; i++)
    printf("%02x", data[i]);
}

/* Parse a hex string into exactly expected_len bytes.
 * Returns 0 on success, -1 on NULL / malformed / wrong-length input. */
static int parse_hex(const char *hex_str, uint8_t *out, size_t expected_len) {
  if (hex_str == NULL)
    return -1;
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X'))
    hex_str += 2;

  size_t hex_len = strlen(hex_str);
  if (hex_len != expected_len * 2)
    return -1;

  for (size_t i = 0; i < expected_len; i++) {
    unsigned int byte;
    if (sscanf(hex_str + 2 * i, "%2x", &byte) != 1)
      return -1;
    out[i] = (uint8_t)byte;
  }
  return 0;
}

static int read_urandom(uint8_t *buf, size_t len) {
  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return -1;
  }
  size_t got = fread(buf, 1, len, urandom);
  fclose(urandom);
  if (got != len) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return -1;
  }
  return 0;
}

/* ── generate_random_plaintext ───────────────────────────────────────── */

static int cmd_generate_random_plaintext(void) {
  uint8_t pt[AIM_BLOCK];
  if (read_urandom(pt, AIM_BLOCK) != 0)
    return 1;
  printf("plaintext: ");
  print_hex(pt, AIM_BLOCK);
  printf("\n");
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

/* ── generate_secrets (no-op for a hash task) ────────────────────────── */

static int cmd_generate_secrets(void) {
  /* This hash task has no challenger-side secrets: the hidden plaintext is
   * sampled via generate_random_plaintext by the game state. base.py parses
   * stdout for ':'-containing lines; printing nothing yields {} and is
   * accepted because required_state_variables() == []. Do NOT print any
   * line containing ':' here (it would inject a bogus game-state attr). */
  return 0;
}

/* ── hash ────────────────────────────────────────────────────────────── */

static int do_hash(const char *pt_hex, const char *iv_hex) {
  if (!pt_hex) {
    fprintf(stderr, "Error: 'plaintext' is required for the hash command\n");
    return 1;
  }

  uint8_t p[AIM_BLOCK];
  uint8_t iv[AIM_BLOCK];
  uint8_t c[AIM_BLOCK];

  if (parse_hex(pt_hex, p, AIM_BLOCK) != 0) {
    fprintf(stderr,
            "Error: Invalid plaintext format. Expected %d hex characters "
            "(%d bytes)\n",
            AIM_BLOCK * 2, AIM_BLOCK);
    return 1;
  }

  if (iv_hex) {
    if (parse_hex(iv_hex, iv, AIM_BLOCK) != 0) {
      fprintf(stderr,
              "Error: Invalid iv format. Expected %d hex characters "
              "(%d bytes)\n",
              AIM_BLOCK * 2, AIM_BLOCK);
      return 1;
    }
  } else {
    if (read_urandom(iv, AIM_BLOCK) != 0)
      return 1;
  }

  aim2(c, p, iv);

  /* The game requires the iv to be echoed (it errors out otherwise) so the
   * adversary always learns which iv produced this digest. */
  printf("iv: ");
  print_hex(iv, AIM_BLOCK);
  printf("\n");
  printf("hash: ");
  print_hex(c, AIM_BLOCK);
  printf("\n");
  return 0;
}

static int cmd_hash_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for hash\n");
    return 1;
  }
  int rc = do_hash(stdin_kv_get(&block, "plaintext"),
                   stdin_kv_get(&block, "iv"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_hash_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = do_hash(stdin_kv_get(&block, "plaintext"),
                     stdin_kv_get(&block, "iv"));
    stdin_kv_free(&block);
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
  } else if (strcmp(args.command, "hash") == 0) {
    if (args.batch)
      return cmd_hash_batch();
    return cmd_hash_stdin();
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
