#define _POSIX_C_SOURCE 200809L

#include "api.h"
#include "cli_stdin.h"
#include "sign.h"
#include <argp.h>
#include <errno.h>
#include <openssl/sha.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── HiMQ-3 buffer sizes ─────────────────────────────────────────────────
 *
 * The HiMQ-3 round-1 reference implementation uses a non-standard NIST API:
 *
 *   - crypto_sign_keypair(pk, sk) fills pk across M*PKWID = PKSIZE bytes and
 *     sk across MM + NN + (F coefficient region) bytes. The actual buffer
 *     sizes are PKSIZE (public) and SKSIZE (secret), NOT the (inconsistent)
 *     CRYPTO_PUBLICKEYBYTES / CRYPTO_SECRETKEYBYTES macros in api.h. We use
 *     the sizes the reference test harness (test.c signtest1) actually
 *     allocates: pk = PKSIZE, sk = SKSIZE.
 *   - crypto_sign(sm, &smlen, m, mlen, sk) expects m to be exactly M bytes
 *     and writes ONLY the N-byte signature to sm (it does not prepend or
 *     append the message and does not set smlen).
 *   - crypto_sign_open(m, &mlen, sm, smlen, pk) treats sm as an N-byte
 *     signature, evaluates the M public polynomials on it and writes the
 *     recovered M-byte message digest to m (the caller must set *mlen = M
 *     beforehand). It does NOT compare against anything and does not return a
 *     meaningful status — verification is the caller's job.
 *
 * Because the security game signs arbitrary-length messages, we hash every
 * message down to an M-byte digest with SHA-512 (truncated to M bytes, since
 * M < 64) before signing/verifying. This is a CLI-side convention only; the
 * upstream HiMQ-3 sources are used verbatim.
 */
#define HIMQ3_PK_BYTES PKSIZE /* 75*75*44 = 247500 */
#define HIMQ3_SK_BYTES SKSIZE /* 75*75*44 + 44*44 + 75*75 = 255061 */
#define HIMQ3_SIG_BYTES N     /* 75 */
#define HIMQ3_DIGEST_BYTES M  /* 44 */

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "himq3-sign 1.0";
static const char doc[] =
    "HiMQ-3 Signature CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random keypair\n"
    "  generate_random_plaintext  Generate a random 32-byte message\n"
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

/* Hash an arbitrary-length message down to an M-byte HiMQ-3 message digest.
 * HiMQ-3 itself signs a fixed M-byte field-element vector; we derive it from
 * the caller's message with SHA-512 truncated to M bytes (M = 44 < 64). */
static void himq3_hash_message(const unsigned char *msg, size_t msg_len,
                               unsigned char *digest_out) {
  unsigned char hash[SHA512_DIGEST_LENGTH];
  SHA512(msg, msg_len, hash);
  memcpy(digest_out, hash, HIMQ3_DIGEST_BYTES);
}

/* ── Commands ────────────────────────────────────────────────────────── */

static int cmd_generate_secrets(void) {
  unsigned char *pk = calloc(HIMQ3_PK_BYTES, 1);
  unsigned char *sk = calloc(HIMQ3_SK_BYTES, 1);

  if (!pk || !sk) {
    fprintf(stderr, "Error: Memory allocation failed\n");
    free(pk);
    free(sk);
    return 1;
  }

  /* HiMQ-3's crypto_sign_keypair seeds its own PRNG via srand(time(NULL)). */
  crypto_sign_keypair(pk, sk);

  printf("private_key: ");
  print_hex(sk, HIMQ3_SK_BYTES);
  printf("\n");

  printf("public_key: ");
  print_hex(pk, HIMQ3_PK_BYTES);
  printf("\n");

  free(pk);
  free(sk);
  return 0;
}

#define PLAINTEXT_LEN 32

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
    fprintf(stderr, "Error: --private-key is required for the sign command\n");
    return 1;
  }
  if (!msg_hex) {
    fprintf(stderr, "Error: --message is required for the sign command\n");
    return 1;
  }

  /* Parse private key */
  unsigned char *sk = malloc(HIMQ3_SK_BYTES);
  if (!sk) {
    fprintf(stderr, "Error: Memory allocation failed for private key\n");
    return 1;
  }

  int sk_len = parse_hex(sk_hex, sk, HIMQ3_SK_BYTES);
  if (sk_len < 0) {
    fprintf(stderr, "Error: Failed to parse private key\n");
    free(sk);
    return 1;
  }

  if (sk_len != HIMQ3_SK_BYTES) {
    fprintf(stderr, "Error: Private key must be exactly %d bytes (got %d)\n",
            HIMQ3_SK_BYTES, sk_len);
    free(sk);
    return 1;
  }

  /* Determine message length from hex input (may be empty) */
  int mlen = hex_byte_len(msg_hex);
  if (mlen < 0) {
    fprintf(stderr, "Error: Invalid message hex format\n");
    free(sk);
    return 1;
  }

  unsigned char *m = malloc(mlen > 0 ? (size_t)mlen : 1);
  if (!m) {
    fprintf(stderr, "Error: Memory allocation failed for message\n");
    free(sk);
    return 1;
  }

  if (mlen > 0 && parse_hex(msg_hex, m, mlen) < 0) {
    fprintf(stderr, "Error: Failed to parse message\n");
    free(sk);
    free(m);
    return 1;
  }

  /* Hash the message down to a fixed M-byte HiMQ-3 digest */
  unsigned char digest[HIMQ3_DIGEST_BYTES];
  himq3_hash_message(m, (size_t)mlen, digest);

  /* crypto_sign writes exactly N signature bytes to sm */
  unsigned char *sm = calloc(HIMQ3_SIG_BYTES, 1);
  if (!sm) {
    fprintf(stderr, "Error: Memory allocation failed for signature\n");
    free(sk);
    free(m);
    return 1;
  }

  unsigned long long smlen = HIMQ3_SIG_BYTES;
  crypto_sign(sm, &smlen, digest, (unsigned long long)HIMQ3_DIGEST_BYTES, sk);

  printf("signature: ");
  print_hex(sm, HIMQ3_SIG_BYTES);
  printf("\n");

  free(sk);
  free(m);
  free(sm);
  return 0;
}

static int cmd_verify(const char *pk_hex, const char *msg_hex,
                      const char *sig_hex) {
  if (!pk_hex) {
    fprintf(stderr, "Error: --public-key is required for the verify command\n");
    return 1;
  }
  if (!msg_hex) {
    fprintf(stderr, "Error: --message is required for the verify command\n");
    return 1;
  }
  if (!sig_hex) {
    fprintf(stderr, "Error: --signature is required for the verify command\n");
    return 1;
  }

  /* Parse public key */
  unsigned char *pk = malloc(HIMQ3_PK_BYTES);
  if (!pk) {
    fprintf(stderr, "Error: Memory allocation failed for public key\n");
    return 1;
  }

  int pk_len = parse_hex(pk_hex, pk, HIMQ3_PK_BYTES);
  if (pk_len < 0) {
    fprintf(stderr, "Error: Failed to parse public key\n");
    free(pk);
    return 1;
  }

  if (pk_len != HIMQ3_PK_BYTES) {
    fprintf(stderr, "Error: Public key must be exactly %d bytes (got %d)\n",
            HIMQ3_PK_BYTES, pk_len);
    free(pk);
    return 1;
  }

  /* Determine message length (may be empty) */
  int mlen = hex_byte_len(msg_hex);
  if (mlen < 0) {
    fprintf(stderr, "Error: Invalid message hex format\n");
    free(pk);
    return 1;
  }

  /* Parse signature: must be exactly N bytes. A wrong-length signature is
   * simply an invalid signature (not a CLI error). */
  unsigned char sig[HIMQ3_SIG_BYTES];
  int sig_byte_len = hex_byte_len(sig_hex);
  if (sig_byte_len != HIMQ3_SIG_BYTES) {
    printf("valid: false\n");
    free(pk);
    return 0;
  }
  if (parse_hex(sig_hex, sig, HIMQ3_SIG_BYTES) != HIMQ3_SIG_BYTES) {
    printf("valid: false\n");
    free(pk);
    return 0;
  }

  /* Parse message */
  unsigned char *m = malloc(mlen > 0 ? (size_t)mlen : 1);
  if (!m) {
    fprintf(stderr, "Error: Memory allocation failed for message\n");
    free(pk);
    return 1;
  }

  if (mlen > 0 && parse_hex(msg_hex, m, mlen) < 0) {
    fprintf(stderr, "Error: Failed to parse message\n");
    free(pk);
    free(m);
    return 1;
  }

  /* Recompute the expected M-byte digest */
  unsigned char expected[HIMQ3_DIGEST_BYTES];
  himq3_hash_message(m, (size_t)mlen, expected);

  /* Evaluate the public map on the signature to recover the digest.
   * crypto_sign_open uses *mlen as the number of polynomials to evaluate. */
  unsigned char recovered[HIMQ3_DIGEST_BYTES];
  unsigned long long out_mlen = HIMQ3_DIGEST_BYTES;
  crypto_sign_open(recovered, &out_mlen, sig,
                   (unsigned long long)HIMQ3_SIG_BYTES, pk);

  int valid = (memcmp(recovered, expected, HIMQ3_DIGEST_BYTES) == 0);
  printf("valid: %s\n", valid ? "true" : "false");

  free(pk);
  free(m);
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
