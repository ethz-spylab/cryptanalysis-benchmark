#define _POSIX_C_SOURCE 200809L

#include "api.h"
#include "cli_stdin.h"
#include <argp.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Lizard upstream API ─────────────────────────────────────────────────
 * Lizard ships its own CSPRNG-backed randombytes() (reads /dev/urandom), so
 * there is no NIST DRBG / rng.h to seed (unlike the classic_mceliece template
 * this is adapted from — the init_rng() helper has been removed).
 *
 * crypto_kem_dec() reads its private-key argument as the concatenation
 * sk‖pk (it indexes sk[CRYPTO_SECRETKEYBYTES + ...] to reach the public key
 * stored after the secret key). We therefore export the *combined*
 * decapsulation key as `private_key`, sized
 * CRYPTO_SECRETKEYBYTES + CRYPTO_PUBLICKEYBYTES. */
int crypto_kem_keypair(unsigned char *pk, unsigned char *sk);
int crypto_kem_enc(unsigned char *ct, unsigned char *ss, const unsigned char *pk);
int crypto_kem_dec(unsigned char *ss, const unsigned char *ct,
                   const unsigned char *sk);

#define DEC_KEYBYTES (CRYPTO_SECRETKEYBYTES + CRYPTO_PUBLICKEYBYTES)

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "kem-cli 1.0";
static const char doc[] =
    "KEM CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random keypair\n"
    "  generate_random_plaintext  Not applicable for KEM (returns empty)\n"
    "  encapsulate                Create a shared secret and encapsulation\n"
    "  decapsulate                Recover the shared secret\n"
    "\n"
    "All hex values are raw byte encodings (same format as PQCgenKAT_kem).\n"
    "The optional 0x prefix is stripped automatically.\n"
    "Arguments can be passed via flags or via stdin as 'key: value' lines.\n"
    "Use --batch for multiple queries separated by '---' lines.";

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"public-key", 'p', "HEX", 0, "Public key in hex (for encapsulate)", 0},
    {"private-key", 's', "HEX", 0, "Private key in hex (for decapsulate)", 0},
    {"encapsulation", 'e', "HEX", 0,
     "Encapsulation / ciphertext in hex (for decapsulate)", 0},
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *public_key;
  const char *private_key;
  const char *encapsulation;
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
  case 'e':
    args->encapsulation = arg;
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
  unsigned char pk[CRYPTO_PUBLICKEYBYTES];
  /* private_key carries sk‖pk because crypto_kem_dec needs both. */
  unsigned char dec_key[DEC_KEYBYTES] = {0};

  int ret = crypto_kem_keypair(pk, dec_key);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_kem_keypair failed with code %d\n", ret);
    return 1;
  }

  /* Append the public key after the secret key so the resulting blob is a
   * complete decapsulation key. */
  memcpy(dec_key + CRYPTO_SECRETKEYBYTES, pk, CRYPTO_PUBLICKEYBYTES);

  printf("private_key: ");
  print_hex(dec_key, DEC_KEYBYTES);
  printf("\n");

  printf("public_key: ");
  print_hex(pk, CRYPTO_PUBLICKEYBYTES);
  printf("\n");

  return 0;
}

static int cmd_generate_random_plaintext(void) {
  printf("\n");
  return 0;
}

static int cmd_encapsulate(const char *pk_hex) {
  if (!pk_hex) {
    fprintf(stderr,
            "Error: --public-key is required for the encapsulate command\n");
    return 1;
  }

  unsigned char pk[CRYPTO_PUBLICKEYBYTES];
  unsigned char ct[CRYPTO_CIPHERTEXTBYTES];
  unsigned char ss[CRYPTO_BYTES];

  int pk_len = parse_hex(pk_hex, pk, CRYPTO_PUBLICKEYBYTES);
  if (pk_len < 0) {
    fprintf(stderr, "Error: Failed to parse public key\n");
    return 1;
  }

  if (pk_len != CRYPTO_PUBLICKEYBYTES) {
    fprintf(stderr, "Error: Public key must be exactly %d bytes (got %d)\n",
            CRYPTO_PUBLICKEYBYTES, pk_len);
    return 1;
  }

  int ret = crypto_kem_enc(ct, ss, pk);
  if (ret != 0) {
    fprintf(stderr, "Error: crypto_kem_enc failed with code %d\n", ret);
    return 1;
  }

  printf("shared_secret_key: ");
  print_hex(ss, CRYPTO_BYTES);
  printf("\n");

  printf("encapsulation: ");
  print_hex(ct, CRYPTO_CIPHERTEXTBYTES);
  printf("\n");

  return 0;
}

static int cmd_decapsulate(const char *sk_hex, const char *ct_hex) {
  if (!sk_hex) {
    fprintf(stderr,
            "Error: --private-key is required for the decapsulate command\n");
    return 1;
  }
  if (!ct_hex) {
    fprintf(stderr,
            "Error: --encapsulation is required for the decapsulate command\n");
    return 1;
  }

  unsigned char sk[DEC_KEYBYTES];
  unsigned char ct[CRYPTO_CIPHERTEXTBYTES];
  unsigned char ss[CRYPTO_BYTES];

  int sk_len = parse_hex(sk_hex, sk, DEC_KEYBYTES);
  if (sk_len < 0) {
    fprintf(stderr, "Error: Failed to parse private key\n");
    return 1;
  }

  if (sk_len != DEC_KEYBYTES) {
    fprintf(stderr, "Error: Private key must be exactly %d bytes (got %d)\n",
            DEC_KEYBYTES, sk_len);
    return 1;
  }

  int ct_len = parse_hex(ct_hex, ct, CRYPTO_CIPHERTEXTBYTES);
  if (ct_len < 0) {
    fprintf(stderr, "Error: Failed to parse encapsulation\n");
    return 1;
  }

  if (ct_len != CRYPTO_CIPHERTEXTBYTES) {
    fprintf(stderr, "Error: Encapsulation must be exactly %d bytes (got %d)\n",
            CRYPTO_CIPHERTEXTBYTES, ct_len);
    return 1;
  }

  int ret = crypto_kem_dec(ss, ct, sk);
  if (ret != 0) {
    printf("FAILED\n");
    return 0;
  }

  printf("shared_secret_key: ");
  print_hex(ss, CRYPTO_BYTES);
  printf("\n");

  return 0;
}

/* ── Stdin / Batch wrappers ──────────────────────────────────────────── */

static int cmd_encapsulate_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for encapsulate\n");
    return 1;
  }
  int rc = cmd_encapsulate(stdin_kv_get(&block, "public-key"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_decapsulate_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for decapsulate\n");
    return 1;
  }
  int rc = cmd_decapsulate(stdin_kv_get(&block, "private-key"),
                           stdin_kv_get(&block, "encapsulation"));
  stdin_kv_free(&block);
  return rc;
}

static int cmd_encapsulate_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = cmd_encapsulate(stdin_kv_get(&block, "public-key"));
    stdin_kv_free(&block);
    if (rc != 0)
      return rc;
  }
  return 0;
}

static int cmd_decapsulate_batch(void) {
  struct stdin_kv_block block;
  int first = 1;
  while (stdin_read_block(&block) > 0) {
    if (!first)
      printf("---\n");
    first = 0;
    int rc = cmd_decapsulate(stdin_kv_get(&block, "private-key"),
                             stdin_kv_get(&block, "encapsulation"));
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
  } else if (strcmp(args.command, "encapsulate") == 0) {
    if (args.batch)
      return cmd_encapsulate_batch();
    if (!args.public_key)
      return cmd_encapsulate_stdin();
    return cmd_encapsulate(args.public_key);
  } else if (strcmp(args.command, "decapsulate") == 0) {
    if (args.batch)
      return cmd_decapsulate_batch();
    if (!args.private_key && !args.encapsulation)
      return cmd_decapsulate_stdin();
    return cmd_decapsulate(args.private_key, args.encapsulation);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
