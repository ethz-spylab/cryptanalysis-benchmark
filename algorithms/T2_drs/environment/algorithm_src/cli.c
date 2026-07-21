#define _POSIX_C_SOURCE 200809L

#include "api.h"
#include "cli_stdin.h"
#include "rng.h"
#include <argp.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "drs-sign 1.0";
static const char doc[] =
    "DRS Signature CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random keypair\n"
    "  generate_random_plaintext  Generate a random 33-byte message\n"
    "  sign                       Sign a message with a private key\n"
    "  verify                     Verify a signature with a public key\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via flags or via stdin as 'key: value' lines.\n"
    "Use --batch for multiple queries separated by '---' lines.";

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

static int init_rng(void) {
  unsigned char entropy_input[48];

  FILE *urandom = fopen("/dev/urandom", "rb");
  if (!urandom) {
    fprintf(stderr, "Error: Failed to open /dev/urandom: %s\n",
            strerror(errno));
    return -1;
  }

  size_t bytes_read = fread(entropy_input, 1, 48, urandom);
  fclose(urandom);

  if (bytes_read != 48) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return -1;
  }

  randombytes_init(entropy_input, NULL, 256);
  return 0;
}

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
  unsigned char *pk = calloc(CRYPTO_PUBLICKEYBYTES, 1);
  unsigned char *sk = calloc(CRYPTO_SECRETKEYBYTES, 1);

  if (!pk || !sk) {
    fprintf(stderr, "Error: Memory allocation failed\n");
    free(pk);
    free(sk);
    return 1;
  }

  if (init_rng() != 0) {
    free(pk);
    free(sk);
    return 1;
  }

  int ret = crypto_sign_keypair(pk, sk);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_sign_keypair failed with code %d\n", ret);
    free(pk);
    free(sk);
    return 1;
  }

  printf("private_key: ");
  print_hex(sk, CRYPTO_SECRETKEYBYTES);
  printf("\n");

  printf("public_key: ");
  print_hex(pk, CRYPTO_PUBLICKEYBYTES);
  printf("\n");

  free(pk);
  free(sk);
  return 0;
}

/* KAT generation uses mlen = 33*(i+1). We use the smallest as a practical
 * default. */
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

  /* Parse private key */
  unsigned char *sk = malloc(CRYPTO_SECRETKEYBYTES);
  if (!sk) {
    fprintf(stderr, "Error: Memory allocation failed for private key\n");
    return 1;
  }

  int sk_len = parse_hex(sk_hex, sk, CRYPTO_SECRETKEYBYTES);
  if (sk_len < 0) {
    fprintf(stderr, "Error: Failed to parse private key\n");
    free(sk);
    return 1;
  }

  if (sk_len != CRYPTO_SECRETKEYBYTES) {
    fprintf(stderr, "Error: Private key must be exactly %d bytes (got %d)\n",
            CRYPTO_SECRETKEYBYTES, sk_len);
    free(sk);
    return 1;
  }

  /* Determine message length from hex input */
  int mlen = hex_byte_len(msg_hex);
  if (mlen <= 0) {
    fprintf(stderr, "Error: Invalid message hex format\n");
    free(sk);
    return 1;
  }

  unsigned char *m = malloc(mlen);
  if (!m) {
    fprintf(stderr, "Error: Memory allocation failed for message\n");
    free(sk);
    return 1;
  }

  if (parse_hex(msg_hex, m, mlen) < 0) {
    fprintf(stderr, "Error: Failed to parse message\n");
    free(sk);
    free(m);
    return 1;
  }

  /* Allocate signed message buffer: message + signature */
  size_t sm_buf_size = (size_t)mlen + CRYPTO_BYTES;
  unsigned char *sm = calloc(sm_buf_size, 1);
  if (!sm) {
    fprintf(stderr, "Error: Memory allocation failed for signed message\n");
    free(sk);
    free(m);
    return 1;
  }

  /* NOTE: DRS signing is deterministic given the secret key — it re-seeds its
   * own seedexpander (`_UniRand_`) from a seed stored inside the secret key
   * (`sk->RandSeed`) and does NOT draw from the NIST DRBG. Calling init_rng()
   * here (randombytes_init) corrupts the shared OpenSSL AES state that the
   * seedexpander relies on, which desyncs the matrix signs regenerated during
   * signing and makes verification fail. So we intentionally do NOT seed the
   * DRBG before crypto_sign. */

  unsigned long long smlen = 0;
  int ret = crypto_sign(sm, &smlen, m, (unsigned long long)mlen, sk);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_sign failed with code %d\n", ret);
    free(sk);
    free(m);
    free(sm);
    return 1;
  }

  /* DRS lays sm out as: signature (CRYPTO_BYTES) || message (mlen). */
  printf("signature: ");
  print_hex(sm, CRYPTO_BYTES);
  printf("\n");

  free(sk);
  free(m);
  free(sm);
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

  /* Parse public key */
  unsigned char *pk = malloc(CRYPTO_PUBLICKEYBYTES);
  if (!pk) {
    fprintf(stderr, "Error: Memory allocation failed for public key\n");
    return 1;
  }

  int pk_len = parse_hex(pk_hex, pk, CRYPTO_PUBLICKEYBYTES);
  if (pk_len < 0) {
    fprintf(stderr, "Error: Failed to parse public key\n");
    free(pk);
    return 1;
  }

  if (pk_len != CRYPTO_PUBLICKEYBYTES) {
    fprintf(stderr, "Error: Public key must be exactly %d bytes (got %d)\n",
            CRYPTO_PUBLICKEYBYTES, pk_len);
    free(pk);
    return 1;
  }

  /* Determine message length */
  int mlen = hex_byte_len(msg_hex);
  if (mlen <= 0) {
    fprintf(stderr, "Error: Invalid message hex format\n");
    free(pk);
    return 1;
  }

  /* Parse signature (MQDSS signatures are large, so allocate on the heap) */
  unsigned char *sig = malloc(CRYPTO_BYTES);
  if (!sig) {
    fprintf(stderr, "Error: Memory allocation failed for signature\n");
    free(pk);
    return 1;
  }

  int sig_len = parse_hex(sig_hex, sig, CRYPTO_BYTES);
  if (sig_len < 0) {
    fprintf(stderr, "Error: Failed to parse signature\n");
    free(pk);
    free(sig);
    return 1;
  }

  if (sig_len != CRYPTO_BYTES) {
    fprintf(stderr, "Error: Signature must be exactly %d bytes (got %d)\n",
            CRYPTO_BYTES, sig_len);
    free(pk);
    free(sig);
    return 1;
  }

  /* Parse message */
  unsigned char *m = malloc(mlen);
  if (!m) {
    fprintf(stderr, "Error: Memory allocation failed for message\n");
    free(pk);
    free(sig);
    return 1;
  }

  if (parse_hex(msg_hex, m, mlen) < 0) {
    fprintf(stderr, "Error: Failed to parse message\n");
    free(pk);
    free(sig);
    free(m);
    return 1;
  }

  /* MQDSS expects sm = signature || message (signature first). */
  size_t smlen = (size_t)mlen + CRYPTO_BYTES;
  unsigned char *sm = malloc(smlen);
  if (!sm) {
    fprintf(stderr, "Error: Memory allocation failed for signed message\n");
    free(pk);
    free(sig);
    free(m);
    return 1;
  }
  memcpy(sm, sig, CRYPTO_BYTES);
  memcpy(sm + CRYPTO_BYTES, m, mlen);

  /* Verify */
  unsigned char *m_out = malloc(smlen);
  if (!m_out) {
    fprintf(stderr, "Error: Memory allocation failed for output message\n");
    free(pk);
    free(m);
    free(sm);
    return 1;
  }

  unsigned long long mlen_out = 0;
  int ret =
      crypto_sign_open(m_out, &mlen_out, sm, (unsigned long long)smlen, pk);

  if (ret != 0) {
    printf("valid: false\n");
  } else {
    printf("valid: true\n");
  }

  free(pk);
  free(sig);
  free(m);
  free(sm);
  free(m_out);
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
