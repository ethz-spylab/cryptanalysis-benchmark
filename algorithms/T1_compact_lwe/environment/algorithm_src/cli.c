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

const char *argp_program_version = "compact-lwe-encrypt 1.0";
static const char doc[] =
    "Compact-LWE Encryption CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random keypair\n"
    "  generate_random_plaintext  Generate a random 16-byte plaintext\n"
    "  encrypt                    Encrypt a plaintext with a public key\n"
    "  decrypt                    Decrypt a ciphertext with a private key\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via flags or via stdin as 'key: value' lines.\n"
    "Use --batch for multiple queries separated by '---' lines.";

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"public-key", 'p', "HEX", 0, "Public key in hex (for encrypt)", 0},
    {"private-key", 's', "HEX", 0, "Private key in hex (for decrypt)", 0},
    {"plaintext", 'm', "HEX", 0, "Plaintext in hex (for encrypt)", 0},
    {"ciphertext", 'c', "HEX", 0, "Ciphertext in hex (for decrypt)", 0},
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *public_key;
  const char *private_key;
  const char *plaintext;
  const char *ciphertext;
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

/* Compact-LWE has a fixed message length of 16 bytes (matches the NIST KAT).
 * Its ciphertext length is variable (group_size * single_clen), but always
 * bounded by CRYPTO_BYTES (the maximum ciphertext buffer declared in api.h).
 * We therefore size buffers with CRYPTO_BYTES and emit/accept the actual
 * length reported by crypto_encrypt. */
#define PLAINTEXT_LEN 16
#define CIPHERTEXT_MAX_BYTES (CRYPTO_BYTES)

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
  unsigned char *pk = malloc(CRYPTO_PUBLICKEYBYTES);
  unsigned char *sk = malloc(CRYPTO_SECRETKEYBYTES);

  if (!pk || !sk) {
    fprintf(stderr, "Error: Memory allocation failed for keypair\n");
    free(pk);
    free(sk);
    return 1;
  }

  if (init_rng() != 0) {
    free(pk);
    free(sk);
    return 1;
  }

  int ret = crypto_encrypt_keypair(pk, sk);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_encrypt_keypair failed with code %d\n", ret);
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

static int cmd_encrypt(const char *pk_hex, const char *pt_hex) {
  if (!pk_hex) {
    fprintf(stderr,
            "Error: --public-key is required for the encrypt command\n");
    return 1;
  }
  if (!pt_hex) {
    fprintf(stderr,
            "Error: --plaintext is required for the encrypt command\n");
    return 1;
  }

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

  unsigned char m[PLAINTEXT_LEN];
  int m_len = parse_hex(pt_hex, m, PLAINTEXT_LEN);
  if (m_len < 0) {
    fprintf(stderr, "Error: Failed to parse plaintext\n");
    free(pk);
    return 1;
  }

  if (m_len != PLAINTEXT_LEN) {
    fprintf(stderr, "Error: Plaintext must be exactly %d bytes (got %d)\n",
            PLAINTEXT_LEN, m_len);
    free(pk);
    return 1;
  }

  if (init_rng() != 0) {
    free(pk);
    return 1;
  }

  unsigned char c[CIPHERTEXT_MAX_BYTES];
  /* crypto_encrypt uses *clen as the size of the available output buffer. */
  unsigned long long clen = (unsigned long long)CIPHERTEXT_MAX_BYTES;
  int ret = crypto_encrypt(c, &clen, m, (unsigned long long)PLAINTEXT_LEN, pk);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_encrypt failed with code %d\n", ret);
    free(pk);
    return 1;
  }

  printf("ciphertext: ");
  print_hex(c, (size_t)clen);
  printf("\n");

  free(pk);
  return 0;
}

static int cmd_decrypt(const char *sk_hex, const char *ct_hex) {
  if (!sk_hex) {
    fprintf(stderr,
            "Error: --private-key is required for the decrypt command\n");
    return 1;
  }
  if (!ct_hex) {
    fprintf(stderr,
            "Error: --ciphertext is required for the decrypt command\n");
    return 1;
  }

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

  unsigned char c[CIPHERTEXT_MAX_BYTES];
  int ct_len = parse_hex(ct_hex, c, CIPHERTEXT_MAX_BYTES);
  if (ct_len < 0) {
    fprintf(stderr, "Error: Failed to parse ciphertext\n");
    free(sk);
    return 1;
  }

  if (ct_len == 0) {
    fprintf(stderr, "Error: Ciphertext must be non-empty\n");
    free(sk);
    return 1;
  }

  /* crypto_encrypt_open may write the decoded message plus internal padding;
   * size the output buffer generously to the ciphertext length. */
  unsigned char m[CIPHERTEXT_MAX_BYTES];
  unsigned long long mlen = 0;

  int ret = crypto_encrypt_open(m, &mlen, c,
                                (unsigned long long)ct_len, sk);
  if (ret != 0) {
    printf("FAILED\n");
    free(sk);
    return 0;
  }

  printf("plaintext: ");
  print_hex(m, (size_t)mlen);
  printf("\n");

  free(sk);
  return 0;
}

/* ── Stdin / Batch wrappers ──────────────────────────────────────────── */

static int cmd_encrypt_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for encrypt\n");
    return 1;
  }
  int rc = cmd_encrypt(stdin_kv_get(&block, "public-key"),
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
  int rc = cmd_decrypt(stdin_kv_get(&block, "private-key"),
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
    int rc = cmd_encrypt(stdin_kv_get(&block, "public-key"),
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
    int rc = cmd_decrypt(stdin_kv_get(&block, "private-key"),
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
    if (!args.public_key && !args.plaintext)
      return cmd_encrypt_stdin();
    return cmd_encrypt(args.public_key, args.plaintext);
  } else if (strcmp(args.command, "decrypt") == 0) {
    if (args.batch)
      return cmd_decrypt_batch();
    if (!args.private_key && !args.ciphertext)
      return cmd_decrypt_stdin();
    return cmd_decrypt(args.private_key, args.ciphertext);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
