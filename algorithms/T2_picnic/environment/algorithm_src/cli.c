#define _POSIX_C_SOURCE 200809L

#include "cli_stdin.h"
#include "picnic.h"
#include <argp.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "sign-cli 1.0";
static const char doc[] =
    "Signature CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random keypair\n"
    "  generate_random_plaintext  Generate a random 33-byte message\n"
    "  sign                       Sign a message with a private key\n"
    "  verify                     Verify a signature with a public key\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via flags or via stdin as 'key: value' lines.\n"
    "Use --batch for multiple queries separated by '---' lines.";

/* Parameter set selected for this task. */
#define SIG_PARAMS Picnic_L1_FS

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"public-key", 'p', "HEX", 0, "Public key in hex (for verify)", 0},
    {"private-key", 's', "HEX", 0, "Private key in hex (for sign)", 0},
    {"message", 'm', "HEX", 0, "Message in hex (for sign/verify)", 0},
    {"signature", 'g', "HEX", 0, "Signature in hex (for verify)", 0},
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *public_key;
  const char *private_key;
  const char *message;
  const char *signature;
  int batch;
  int count;
};

/* ── argp parser ─────────────────────────────────────────────────────── */

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
  struct arguments *args = state->input;
  switch (key) {
  case 'p':
    args->public_key = arg;
    break;
  case 's':
    args->private_key = arg;
    break;
  case 'm':
    args->message = arg;
    break;
  case 'g':
    args->signature = arg;
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

static void print_hex(const unsigned char *data, size_t len) {
  printf("0x");
  for (size_t i = 0; i < len; i++) {
    printf("%02x", data[i]);
  }
}

static int hex_byte_len(const char *hex_str) {
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X')) {
    hex_str += 2;
  }
  size_t hex_len = strlen(hex_str);
  if (hex_len % 2 != 0) {
    return -1;
  }
  return (int)(hex_len / 2);
}

static int parse_hex(const char *hex_str, unsigned char *out, size_t max_len) {
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X')) {
    hex_str += 2;
  }

  size_t hex_len = strlen(hex_str);
  if (hex_len % 2 != 0) {
    fprintf(stderr, "Error: Hex string must have even length\n");
    return -1;
  }

  size_t byte_len = hex_len / 2;
  if (byte_len > max_len) {
    fprintf(stderr, "Error: Hex string too long (max %zu bytes)\n", max_len);
    return -1;
  }

  for (size_t i = 0; i < byte_len; i++) {
    unsigned int byte;
    if (sscanf(hex_str + 2 * i, "%2x", &byte) != 1) {
      fprintf(stderr, "Error: Invalid hex character at position %zu\n", 2 * i);
      return -1;
    }
    out[i] = (unsigned char)byte;
  }

  return (int)byte_len;
}

/* ── Commands ────────────────────────────────────────────────────────── */

static int cmd_generate_secrets(void) {
  picnic_publickey_t pk;
  picnic_privatekey_t sk;

  int ret = picnic_keygen(SIG_PARAMS, &pk, &sk);
  if (ret != 0) {
    fprintf(stderr, "Error: picnic_keygen failed with code %d\n", ret);
    return 1;
  }

  unsigned char pk_buf[PICNIC_MAX_PUBLICKEY_SIZE];
  unsigned char sk_buf[PICNIC_MAX_PRIVATEKEY_SIZE];

  int pk_len = picnic_write_public_key(&pk, pk_buf, sizeof(pk_buf));
  if (pk_len <= 0) {
    fprintf(stderr, "Error: picnic_write_public_key failed\n");
    return 1;
  }

  int sk_len = picnic_write_private_key(&sk, sk_buf, sizeof(sk_buf));
  if (sk_len <= 0) {
    fprintf(stderr, "Error: picnic_write_private_key failed\n");
    return 1;
  }

  printf("private_key: ");
  print_hex(sk_buf, (size_t)sk_len);
  printf("\n");

  printf("public_key: ");
  print_hex(pk_buf, (size_t)pk_len);
  printf("\n");

  return 0;
}

/* Matches the convention of the KAT harness: smallest sensible random message. */
#define PLAINTEXT_LEN 33

static int cmd_generate_random_plaintext(void) {
  unsigned char plaintext[PLAINTEXT_LEN];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return 1;
  }

  size_t bytes_read = fread(plaintext, 1, PLAINTEXT_LEN, urandom);
  fclose(urandom);

  if (bytes_read != PLAINTEXT_LEN) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return 1;
  }

  printf("plaintext: ");
  print_hex(plaintext, PLAINTEXT_LEN);
  printf("\n");

  return 0;
}

static int cmd_sign(const char *sk_hex, const char *msg_hex) {
  if (!sk_hex) {
    fprintf(stderr,
            "Error: --private-key is required for the sign command\n");
    return 1;
  }
  if (!msg_hex) {
    fprintf(stderr, "Error: --message is required for the sign command\n");
    return 1;
  }

  unsigned char sk_buf[PICNIC_MAX_PRIVATEKEY_SIZE];
  int sk_len = parse_hex(sk_hex, sk_buf, sizeof(sk_buf));
  if (sk_len < 0) {
    fprintf(stderr, "Error: Failed to parse private key\n");
    return 1;
  }

  picnic_privatekey_t sk;
  if (picnic_read_private_key(&sk, sk_buf, (size_t)sk_len) != 0) {
    fprintf(stderr, "Error: picnic_read_private_key failed\n");
    return 1;
  }

  int mlen = hex_byte_len(msg_hex);
  if (mlen <= 0) {
    fprintf(stderr, "Error: Invalid message hex format\n");
    return 1;
  }

  unsigned char *m = malloc((size_t)mlen);
  if (!m) {
    fprintf(stderr, "Error: Memory allocation failed for message\n");
    return 1;
  }

  if (parse_hex(msg_hex, m, (size_t)mlen) < 0) {
    fprintf(stderr, "Error: Failed to parse message\n");
    free(m);
    return 1;
  }

  size_t sig_buf_len = picnic_signature_size(SIG_PARAMS);
  unsigned char *sig = calloc(sig_buf_len, 1);
  if (!sig) {
    fprintf(stderr, "Error: Memory allocation failed for signature\n");
    free(m);
    return 1;
  }

  size_t sig_len = sig_buf_len;
  int ret = picnic_sign(&sk, m, (size_t)mlen, sig, &sig_len);
  if (ret != 0) {
    fprintf(stderr, "Error: picnic_sign failed with code %d\n", ret);
    free(m);
    free(sig);
    return 1;
  }

  printf("signature: ");
  print_hex(sig, sig_len);
  printf("\n");

  free(m);
  free(sig);
  return 0;
}

static int cmd_verify(const char *pk_hex, const char *msg_hex,
                      const char *sig_hex) {
  if (!pk_hex) {
    fprintf(stderr,
            "Error: --public-key is required for the verify command\n");
    return 1;
  }
  if (!msg_hex) {
    fprintf(stderr, "Error: --message is required for the verify command\n");
    return 1;
  }
  if (!sig_hex) {
    fprintf(stderr,
            "Error: --signature is required for the verify command\n");
    return 1;
  }

  unsigned char pk_buf[PICNIC_MAX_PUBLICKEY_SIZE];
  int pk_len = parse_hex(pk_hex, pk_buf, sizeof(pk_buf));
  if (pk_len < 0) {
    fprintf(stderr, "Error: Failed to parse public key\n");
    return 1;
  }

  picnic_publickey_t pk;
  if (picnic_read_public_key(&pk, pk_buf, (size_t)pk_len) != 0) {
    fprintf(stderr, "Error: picnic_read_public_key failed\n");
    return 1;
  }

  int mlen = hex_byte_len(msg_hex);
  if (mlen <= 0) {
    fprintf(stderr, "Error: Invalid message hex format\n");
    return 1;
  }

  int sig_len = hex_byte_len(sig_hex);
  if (sig_len <= 0) {
    fprintf(stderr, "Error: Invalid signature hex format\n");
    return 1;
  }

  unsigned char *m = malloc((size_t)mlen);
  unsigned char *sig = malloc((size_t)sig_len);
  if (!m || !sig) {
    fprintf(stderr, "Error: Memory allocation failed\n");
    free(m);
    free(sig);
    return 1;
  }

  if (parse_hex(msg_hex, m, (size_t)mlen) < 0 ||
      parse_hex(sig_hex, sig, (size_t)sig_len) < 0) {
    fprintf(stderr, "Error: Failed to parse input\n");
    free(m);
    free(sig);
    return 1;
  }

  int ret = picnic_verify(&pk, m, (size_t)mlen, sig, (size_t)sig_len);
  free(m);
  free(sig);

  if (ret != 0) {
    printf("valid: false\n");
    return 0;
  }

  printf("valid: true\n");
  return 0;
}

/* ── Stdin / Batch wrappers ──────────────────────────────────────────── */

static int cmd_sign_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for sign\n");
    return 1;
  }
  int rc = cmd_sign(stdin_kv_get(&block, "private-key"),
                    stdin_kv_get(&block, "message"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_verify_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for verify\n");
    return 1;
  }
  int rc = cmd_verify(stdin_kv_get(&block, "public-key"),
                      stdin_kv_get(&block, "message"),
                      stdin_kv_get(&block, "signature"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_sign_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = cmd_sign(stdin_kv_get(&block, "private-key"),
                      stdin_kv_get(&block, "message"));
    stdin_kv_free(&block);
    if (rc != 0)
      return rc;
  }
  return 0;
}

static int cmd_verify_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = cmd_verify(stdin_kv_get(&block, "public-key"),
                        stdin_kv_get(&block, "message"),
                        stdin_kv_get(&block, "signature"));
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
  } else if (strcmp(args.command, "sign") == 0) {
    if (args.batch)
      return cmd_sign_batch();
    if (!args.private_key && !args.message)
      return cmd_sign_stdin();
    return cmd_sign(args.private_key, args.message);
  } else if (strcmp(args.command, "verify") == 0) {
    if (args.batch)
      return cmd_verify_batch();
    if (!args.public_key && !args.message && !args.signature)
      return cmd_verify_stdin();
    return cmd_verify(args.public_key, args.message, args.signature);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
