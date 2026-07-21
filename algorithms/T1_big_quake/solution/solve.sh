#!/bin/bash

# Write the attack C source file
cat <<'EOF' > /app/big_quake_attack.c
/*
 * Oracle Cloning Attack on BIG_QUAKE — Game Session Version
 *
 * Exploits the lack of domain separation in BIG_QUAKE's use of SHA3-256.
 * The ciphertext contains c3 = SHA3-256(m), which allows reconstructing
 * the error vector and recovering the shared secret without the private key.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "api.h"
#include "sizes.h"

/* SHA3-256 from keccak.c */
void FIPS202_SHA3_256(const unsigned char *input, unsigned int inputByteLen,
                      unsigned char *output);

/* ========================================================================
 * Replicated m2error internals (same logic as m2e.c)
 * ======================================================================== */

static unsigned char *atk_buff = NULL;
static int atk_buff_size = 0;

static void atk_init_hash(const unsigned char *data) {
    atk_buff_size = HASH_SIZE;
    atk_buff = realloc(atk_buff, atk_buff_size * sizeof(unsigned char));
    FIPS202_SHA3_256(data, RANDOM_BYTES, atk_buff);
}

static void atk_init_from_c3(const unsigned char *c3) {
    atk_buff_size = HASH_SIZE;
    atk_buff = realloc(atk_buff, atk_buff_size * sizeof(unsigned char));
    memcpy(atk_buff, c3, HASH_SIZE);
}

static unsigned char *atk_hash_trunc(int s) {
    unsigned char *aux = malloc(HASH_SIZE * sizeof(unsigned char));
    atk_buff_size -= s;

    if (atk_buff_size < 0) {
        memcpy(aux, atk_buff, HASH_SIZE);
        atk_init_hash(aux);
        atk_buff_size -= s;
        return realloc(aux, s * sizeof(unsigned char));
    }

    memcpy(aux, atk_buff + atk_buff_size - 1, s * sizeof(unsigned char));
    return aux;
}

static int atk_uchar_to_int(unsigned char *c, int s) {
    int i, res = 0;
    for (i = 0; i < s; i++) {
        res <<= 8;
        res ^= (c[i] & 0xff);
    }
    return res;
}

static int atk_uniform(int s, int module) {
    int res;
    unsigned char *aux;
    while (1) {
        aux = atk_hash_trunc(s);
        res = atk_uchar_to_int(aux, s);
        if (res > ((1 << (s * 8)) - ((1 << (s * 8)) % module))) {
            free(aux);
            continue;
        }
        free(aux);
        return res % module;
    }
}

static void atk_swap(int *permutation, int a, int b) {
    int tmp = permutation[a];
    permutation[a] = permutation[b];
    permutation[b] = tmp;
}

static int hash_to_error(const unsigned char *c3, int *error) {
    int i, j, s = 3;
    int permutation[LENGTH];
    unsigned char *aux = malloc(HASH_SIZE * sizeof(unsigned char));

    for (i = 0; i < LENGTH; ++i)
        permutation[i] = i;

    atk_init_from_c3(c3);

    for (i = 0; i < NB_ERRORS; i++) {
        j = atk_uniform(s, LENGTH - i - 1);
        atk_swap(permutation, i, i + j);

        memcpy(aux, atk_buff, HASH_SIZE);
        atk_init_hash(aux);
    }

    for (i = 0; i < NB_ERRORS; ++i)
        error[i] = permutation[i];

    free(aux);
    return 0;
}

/* ========================================================================
 * Hex parsing helpers
 * ======================================================================== */

static int parse_hex(const char *hex_str, unsigned char *out, size_t max_len) {
    if (hex_str[0] == '0' && (hex_str[1] == 'x' || hex_str[1] == 'X'))
        hex_str += 2;

    size_t hex_len = strlen(hex_str);
    if (hex_len % 2 != 0) return -1;

    size_t byte_len = hex_len / 2;
    if (byte_len > max_len) return -1;

    for (size_t i = 0; i < byte_len; i++) {
        unsigned int byte;
        if (sscanf(hex_str + 2 * i, "%2x", &byte) != 1) return -1;
        out[i] = (unsigned char)byte;
    }
    return (int)byte_len;
}

static void to_hex(const unsigned char *data, size_t len, char *out) {
    out[0] = '0';
    out[1] = 'x';
    for (size_t i = 0; i < len; i++)
        sprintf(out + 2 + 2 * i, "%02x", data[i]);
    out[2 + 2 * len] = '\0';
}

/* ========================================================================
 * Game interaction helpers
 * ======================================================================== */

#define BUFFER_SIZE 65536

static char *run_command(const char *command) {
    FILE *fp = popen(command, "r");
    if (!fp) {
        fprintf(stderr, "Failed to execute command: %s\n", command);
        exit(1);
    }

    static char response[BUFFER_SIZE];
    size_t total = 0;
    size_t bytes;
    while ((bytes = fread(response + total, 1, BUFFER_SIZE - total - 1, fp)) > 0)
        total += bytes;
    response[total] = '\0';

    int rc = pclose(fp);
    if (rc != 0) {
        fprintf(stderr, "Command failed (rc=%d): %s\nOutput: %s\n", rc, command, response);
        exit(1);
    }
    return response;
}

/*
 * Extract the value for a given key from the game_controller_client output.
 * The output format for execute_current_stage is like:
 *   ...public_key='0xabc...' encapsulation='0xdef...'...
 * For oracle_query it returns JSON like:
 *   {"key": "value", ...}
 */
static const char *extract_value(const char *response, const char *key, char *dest, size_t dest_size) {
    char pattern[256];
    const char *start;

    /* Try 'key': 'value' pattern (Pydantic dict repr) */
    snprintf(pattern, sizeof(pattern), "'%s': '", key);
    start = strstr(response, pattern);
    if (start) {
        start += strlen(pattern);
        const char *end = strchr(start, '\'');
        if (end) {
            size_t len = (size_t)(end - start);
            if (len >= dest_size) len = dest_size - 1;
            memcpy(dest, start, len);
            dest[len] = '\0';
            return dest;
        }
    }

    /* Try key='value' pattern */
    snprintf(pattern, sizeof(pattern), "%s='", key);
    start = strstr(response, pattern);
    if (start) {
        start += strlen(pattern);
        const char *end = strchr(start, '\'');
        if (end) {
            size_t len = (size_t)(end - start);
            if (len >= dest_size) len = dest_size - 1;
            memcpy(dest, start, len);
            dest[len] = '\0';
            return dest;
        }
    }

    /* Try JSON "key": "value" pattern */
    snprintf(pattern, sizeof(pattern), "\"%s\": \"", key);
    start = strstr(response, pattern);
    if (!start) {
        snprintf(pattern, sizeof(pattern), "\"%s\":\"", key);
        start = strstr(response, pattern);
    }
    if (start) {
        start = strchr(start + 1, ':');
        if (start) {
            start++;
            while (*start == ' ' || *start == '"') start++;
            const char *end = strchr(start, '"');
            if (end) {
                size_t len = (size_t)(end - start);
                if (len >= dest_size) len = dest_size - 1;
                memcpy(dest, start, len);
                dest[len] = '\0';
                return dest;
            }
        }
    }

    fprintf(stderr, "Failed to find key '%s' in response:\n%.500s\n", key, response);
    exit(1);
    return NULL;
}

/* ========================================================================
 * Main attack
 * ======================================================================== */

int main(void) {
    int i;
    char *response;
    char public_key_hex[BUFFER_SIZE];
    char encapsulation_hex[BUFFER_SIZE];

    printf("=== BIG_QUAKE Oracle Cloning Attack (Game Session) ===\n\n");

    /* Stage 0: Get public key and encapsulation */
    printf("Stage 0: Getting public key and encapsulation...\n");
    response = run_command(
        "uv run /app/game_controller_client.py --action execute_current_stage "
        "--json '{\"stage_payload\": {}}'"
    );
    printf("Stage 0 response: %s\n", response);

    extract_value(response, "public_key", public_key_hex, sizeof(public_key_hex));
    extract_value(response, "encapsulation", encapsulation_hex, sizeof(encapsulation_hex));

    printf("Public key: %.40s...\n", public_key_hex);
    printf("Encapsulation: %.40s...\n", encapsulation_hex);

    /* Parse encapsulation (ciphertext) from hex */
    unsigned char ct[CRYPTO_CIPHERTEXTBYTES];
    int ct_len = parse_hex(encapsulation_hex, ct, CRYPTO_CIPHERTEXTBYTES);
    if (ct_len != CRYPTO_CIPHERTEXTBYTES) {
        fprintf(stderr, "Error: Expected ciphertext of %d bytes, got %d\n",
                CRYPTO_CIPHERTEXTBYTES, ct_len);
        return 1;
    }

    printf("Ciphertext parsed: %d bytes\n", ct_len);

    /* ---- ATTACK (uses only ct, NOT sk) ---- */
    printf("\n--- Running oracle cloning attack ---\n");

    /* Step 1: Parse ciphertext into c1 || syndrome || c3 */
    unsigned char *c1 = ct;                              /* first HASH_SIZE bytes */
    unsigned char *c3 = ct + HASH_SIZE + SYNDROME_BYTES; /* last HASH_SIZE bytes */

    printf("c1 (first %d bytes of ct): ", HASH_SIZE);
    for (i = 0; i < HASH_SIZE && i < 16; i++) printf("%02x", c1[i]);
    printf("...\n");
    printf("c3 (last %d bytes of ct): ", HASH_SIZE);
    for (i = 0; i < HASH_SIZE && i < 16; i++) printf("%02x", c3[i]);
    printf("...\n");

    /* Step 2: Reconstruct error vector from c3 */
    printf("Reconstructing error vector from c3...\n");
    int error[NB_ERRORS];
    hash_to_error(c3, error);

    /* Step 3: Convert error positions to bit vector and hash it */
    unsigned char *e = calloc(BITS_TO_BYTES(LENGTH), sizeof(unsigned char));
    for (i = 0; i < NB_ERRORS; i++)
        e[error[i] / 8] ^= (1 << (error[i] % 8));

    unsigned char hash_e[HASH_SIZE];
    FIPS202_SHA3_256(e, BITS_TO_BYTES(LENGTH), hash_e);

    /* Step 4: Recover m = c1 XOR SHA3-256(e) */
    unsigned char recovered_m[RANDOM_BYTES];
    for (i = 0; i < RANDOM_BYTES; i++)
        recovered_m[i] = c1[i] ^ hash_e[i];

    printf("Recovered m: ");
    for (i = 0; i < RANDOM_BYTES && i < 16; i++) printf("%02x", recovered_m[i]);
    printf("...\n");

    /* Step 5: Compute shared secret = SHA3-256(m || ct) */
    unsigned char *m_ct = malloc(RANDOM_BYTES + CIPHERTEXT_BYTES);
    memcpy(m_ct, recovered_m, RANDOM_BYTES);
    memcpy(m_ct + RANDOM_BYTES, ct, CIPHERTEXT_BYTES);

    unsigned char recovered_ss[CRYPTO_BYTES];
    FIPS202_SHA3_256(m_ct, RANDOM_BYTES + CIPHERTEXT_BYTES, recovered_ss);

    printf("Recovered shared secret: ");
    for (i = 0; i < CRYPTO_BYTES; i++) printf("%02x", recovered_ss[i]);
    printf("\n");

    /* Format as hex string for submission */
    char ss_hex[2 + 2 * CRYPTO_BYTES + 1];
    to_hex(recovered_ss, CRYPTO_BYTES, ss_hex);

    /* Stage 1: Submit recovered shared secret */
    printf("\nStage 1: Submitting recovered shared secret...\n");
    char command[BUFFER_SIZE];
    snprintf(command, sizeof(command),
        "uv run /app/game_controller_client.py --action execute_current_stage "
        "--json '{\"stage_payload\": {\"recovered_shared_secret\": \"%s\"}}'",
        ss_hex);

    response = run_command(command);
    printf("Stage 1 response: %s\n", response);

    /* Check result */
    if (strstr(response, "Yes")) {
        printf("\nSUCCESS: Shared secret recovered correctly!\n");
    } else {
        printf("\nFAILURE: Shared secret recovery failed!\n");
    }

    /* Cleanup */
    free(e);
    free(m_ct);
    if (atk_buff) free(atk_buff);

    return 0;
}
EOF

# Compile the attack program against the BIG_QUAKE sources at /app/algorithm_src/
gcc -O2 -fcommon -o /app/big_quake_attack \
    /app/big_quake_attack.c /app/algorithm_src/keccak.c \
    -I/app/algorithm_src/

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
cd /app
./big_quake_attack
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
