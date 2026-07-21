#define _POSIX_C_SOURCE 200809L

#include "api.h"
#include "cli_stdin.h"
#include "crypto_aead.h"
#include <argp.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Program metadata ────────────────────────────────────────────────── */

const char *argp_program_version = "aead-cli 1.0";
static const char doc[] =
    "AEAD CLI Tool\v"
    "Commands:\n"
    "  generate_secrets           Generate a random key\n"
    "  generate_random_plaintext  Generate a random plaintext of given "
    "length\n"
    "  encrypt                    Encrypt plaintext with optional associated "
    "data\n"
    "  decrypt                    Decrypt ciphertext with optional associated "
    "data\n"
    "\n"
    "All hex values accept an optional 0x prefix.\n"
    "Arguments can be passed via flags or via stdin as 'key: value' lines.\n"
    "Use --batch for multiple queries separated by '---' lines.";

/* ── Option definitions ──────────────────────────────────────────────── */

static struct argp_option options[] = {
    {"key", 'k', "HEX", 0, "Encryption key as hex", 0},
    {"nonce", 'o', "HEX", 0,
     "Public nonce as hex (encrypt: optional, randomly generated if "
     "omitted; decrypt: required)",
     0},
    {"plaintext", 'p', "HEX", 0, "Plaintext as hex (for encrypt)", 0},
    {"ciphertext", 'c', "HEX", 0,
     "Ciphertext including tag as hex (for decrypt)", 0},
    {"ad", 'a', "HEX", 0, "Associated data as hex (optional)", 0},
    {"length", 'l', "N", 0,
     "Plaintext length in bytes for generate_random_plaintext (default: 32)",
     0},
    {"batch", 'b', 0, 0,
     "Read inputs from stdin, one block per query, separated by ---", 0},
    {"count", 'n', "N", 0,
     "Number of outputs for batch generate commands (default: 1)", 0},
    {0}};

struct arguments {
  const char *command;
  const char *key;
  const char *nonce;
  const char *plaintext;
  const char *ciphertext;
  const char *ad;
  int length;
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
  case 'o':
    args->nonce = arg;
    break;
  case 'p':
    args->plaintext = arg;
    break;
  case 'c':
    args->ciphertext = arg;
    break;
  case 'a':
    args->ad = arg;
    break;
  case 'l':
    args->length = atoi(arg);
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

/**
 * Parse a hex string into a byte buffer.
 * If expected_len > 0, the hex string must decode to exactly that many bytes.
 * If expected_len == 0, the buffer is dynamically allocated and *out_len is
 * set. Returns 0 on success, -1 on failure.
 */
static int parse_hex_dynamic(const char *hex_str, uint8_t **out,
                             size_t *out_len, size_t expected_len) {
  if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X')) {
    hex_str += 2;
  }

  size_t hex_len = strlen(hex_str);
  if (hex_len % 2 != 0) {
    return -1;
  }

  size_t byte_len = hex_len / 2;
  if (expected_len > 0 && byte_len != expected_len) {
    return -1;
  }

  uint8_t *buf = malloc(byte_len);
  if (!buf) {
    return -1;
  }

  for (size_t i = 0; i < byte_len; i++) {
    unsigned int byte;
    if (sscanf(hex_str + 2 * i, "%2x", &byte) != 1) {
      free(buf);
      return -1;
    }
    buf[i] = (uint8_t)byte;
  }

  *out = buf;
  if (out_len) {
    *out_len = byte_len;
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
  size_t bytes_read = fread(buf, 1, len, urandom);
  fclose(urandom);
  if (bytes_read != len) {
    fprintf(stderr,
            "Error: Failed to read enough random bytes from /dev/urandom\n");
    return -1;
  }
  return 0;
}

/* ── Commands ────────────────────────────────────────────────────────── */

static int cmd_generate_secrets(void) {
  uint8_t key[CRYPTO_KEYBYTES];

  if (read_urandom(key, CRYPTO_KEYBYTES) != 0)
    return 1;

  printf("key: ");
  print_hex(key, CRYPTO_KEYBYTES);
  printf("\n");

  return 0;
}

static int cmd_generate_random_plaintext(int length) {
  if (length <= 0)
    length = 32;

  uint8_t *pt = malloc((size_t)length);
  if (!pt) {
    fprintf(stderr, "Error: Failed to allocate memory\n");
    return 1;
  }

  if (read_urandom(pt, (size_t)length) != 0) {
    free(pt);
    return 1;
  }

  printf("plaintext: ");
  print_hex(pt, (size_t)length);
  printf("\n");

  free(pt);
  return 0;
}

static int cmd_encrypt(const char *key_hex, const char *nonce_hex,
                       const char *pt_hex, const char *ad_hex) {
  if (!key_hex) {
    fprintf(stderr, "Error: --key is required for the encrypt command\n");
    return 1;
  }
  if (!pt_hex) {
    fprintf(stderr, "Error: --plaintext is required for the encrypt command\n");
    return 1;
  }

  uint8_t *key = NULL, *nonce = NULL, *pt = NULL, *ad = NULL;
  size_t pt_len = 0, ad_len = 0;
  int rc = 1;

  if (parse_hex_dynamic(key_hex, &key, NULL, CRYPTO_KEYBYTES) != 0) {
    fprintf(stderr, "Error: Invalid key format. Expected %d hex characters\n",
            CRYPTO_KEYBYTES * 2);
    goto cleanup;
  }

  if (nonce_hex) {
    if (parse_hex_dynamic(nonce_hex, &nonce, NULL, CRYPTO_NPUBBYTES) != 0) {
      fprintf(stderr,
              "Error: Invalid nonce format. Expected %d hex characters\n",
              CRYPTO_NPUBBYTES * 2);
      goto cleanup;
    }
  } else {
    nonce = malloc(CRYPTO_NPUBBYTES);
    if (!nonce) {
      fprintf(stderr, "Error: Failed to allocate memory\n");
      goto cleanup;
    }
    if (read_urandom(nonce, CRYPTO_NPUBBYTES) != 0) {
      goto cleanup;
    }
  }

  if (parse_hex_dynamic(pt_hex, &pt, &pt_len, 0) != 0) {
    fprintf(stderr, "Error: Invalid plaintext format\n");
    goto cleanup;
  }

  if (ad_hex) {
    if (parse_hex_dynamic(ad_hex, &ad, &ad_len, 0) != 0) {
      fprintf(stderr, "Error: Invalid associated data format\n");
      goto cleanup;
    }
  }

  /* ciphertext buffer: plaintext + tag */
  size_t ct_alloc = pt_len + CRYPTO_ABYTES;
  uint8_t *ct = malloc(ct_alloc);
  if (!ct) {
    fprintf(stderr, "Error: Failed to allocate memory\n");
    goto cleanup;
  }

  unsigned long long ct_len = 0;
  int ret = crypto_aead_encrypt(ct, &ct_len, pt, (unsigned long long)pt_len, ad,
                                (unsigned long long)ad_len, NULL, nonce, key);
  if (ret != 0) {
    fprintf(stderr, "Error: Encryption failed (return code %d)\n", ret);
    free(ct);
    goto cleanup;
  }

  printf("nonce: ");
  print_hex(nonce, CRYPTO_NPUBBYTES);
  printf("\n");
  printf("ciphertext: ");
  print_hex(ct, (size_t)ct_len);
  printf("\n");

  free(ct);
  rc = 0;

cleanup:
  free(key);
  free(nonce);
  free(pt);
  free(ad);
  return rc;
}

static int cmd_decrypt(const char *key_hex, const char *nonce_hex,
                       const char *ct_hex, const char *ad_hex) {
  if (!key_hex) {
    fprintf(stderr, "Error: --key is required for the decrypt command\n");
    return 1;
  }
  if (!nonce_hex) {
    fprintf(stderr, "Error: --nonce is required for the decrypt command\n");
    return 1;
  }
  if (!ct_hex) {
    fprintf(stderr,
            "Error: --ciphertext is required for the decrypt command\n");
    return 1;
  }

  uint8_t *key = NULL, *nonce = NULL, *ct = NULL, *ad = NULL;
  size_t ct_len = 0, ad_len = 0;
  int rc = 1;

  if (parse_hex_dynamic(key_hex, &key, NULL, CRYPTO_KEYBYTES) != 0) {
    fprintf(stderr, "Error: Invalid key format. Expected %d hex characters\n",
            CRYPTO_KEYBYTES * 2);
    goto cleanup;
  }

  if (parse_hex_dynamic(nonce_hex, &nonce, NULL, CRYPTO_NPUBBYTES) != 0) {
    fprintf(stderr,
            "Error: Invalid nonce format. Expected %d hex characters\n",
            CRYPTO_NPUBBYTES * 2);
    goto cleanup;
  }

  if (parse_hex_dynamic(ct_hex, &ct, &ct_len, 0) != 0) {
    fprintf(stderr, "Error: Invalid ciphertext format\n");
    goto cleanup;
  }

  if (ct_len < CRYPTO_ABYTES) {
    fprintf(stderr,
            "Error: Ciphertext too short (must be at least %d bytes for tag)\n",
            CRYPTO_ABYTES);
    goto cleanup;
  }

  if (ad_hex) {
    if (parse_hex_dynamic(ad_hex, &ad, &ad_len, 0) != 0) {
      fprintf(stderr, "Error: Invalid associated data format\n");
      goto cleanup;
    }
  }

  /* plaintext buffer: ciphertext - tag */
  size_t pt_alloc = ct_len - CRYPTO_ABYTES;
  uint8_t *pt = malloc(pt_alloc > 0 ? pt_alloc : 1);
  if (!pt) {
    fprintf(stderr, "Error: Failed to allocate memory\n");
    goto cleanup;
  }

  unsigned long long pt_len = 0;
  int ret = crypto_aead_decrypt(pt, &pt_len, NULL, ct,
                                (unsigned long long)ct_len, ad,
                                (unsigned long long)ad_len, nonce, key);
  if (ret != 0) {
    fprintf(stderr, "Error: Authentication failed\n");
    free(pt);
    goto cleanup;
  }

  printf("plaintext: ");
  print_hex(pt, (size_t)pt_len);
  printf("\n");

  free(pt);
  rc = 0;

cleanup:
  free(key);
  free(nonce);
  free(ct);
  free(ad);
  return rc;
}

/* ── Stdin / Batch wrappers ──────────────────────────────────────────── */

static int cmd_encrypt_stdin(void) {
  struct stdin_kv_block block;
  if (stdin_read_block(&block) <= 0) {
    fprintf(stderr, "Error: No input on stdin for encrypt\n");
    return 1;
  }
  int rc = cmd_encrypt(stdin_kv_get(&block, "key"),
                       stdin_kv_get(&block, "nonce"),
                       stdin_kv_get(&block, "plaintext"),
                       stdin_kv_get(&block, "ad"));
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
                       stdin_kv_get(&block, "nonce"),
                       stdin_kv_get(&block, "ciphertext"),
                       stdin_kv_get(&block, "ad"));
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
                         stdin_kv_get(&block, "nonce"),
                         stdin_kv_get(&block, "plaintext"),
                         stdin_kv_get(&block, "ad"));
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
                         stdin_kv_get(&block, "nonce"),
                         stdin_kv_get(&block, "ciphertext"),
                         stdin_kv_get(&block, "ad"));
    stdin_kv_free(&block);
    if (rc != 0)
      return rc;
  }
  return 0;
}

static int cmd_generate_random_plaintext_batch(int count, int length) {
  for (int i = 0; i < count; i++) {
    if (i > 0)
      printf("---\n");
    int rc = cmd_generate_random_plaintext(length);
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
      return cmd_generate_random_plaintext_batch(
          args.count > 0 ? args.count : 1, args.length);
    return cmd_generate_random_plaintext(args.length);
  } else if (strcmp(args.command, "encrypt") == 0) {
    if (args.batch)
      return cmd_encrypt_batch();
    if (!args.key && !args.nonce && !args.plaintext)
      return cmd_encrypt_stdin();
    return cmd_encrypt(args.key, args.nonce, args.plaintext, args.ad);
  } else if (strcmp(args.command, "decrypt") == 0) {
    if (args.batch)
      return cmd_decrypt_batch();
    if (!args.key && !args.nonce && !args.ciphertext)
      return cmd_decrypt_stdin();
    return cmd_decrypt(args.key, args.nonce, args.ciphertext, args.ad);
  } else {
    fprintf(stderr, "Error: Unknown command '%s'\n", args.command);
    return 1;
  }
}
