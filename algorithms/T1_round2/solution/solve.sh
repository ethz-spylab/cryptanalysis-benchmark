#!/bin/bash

# Write the Round2 oracle cloning attack C code
cat <<'ATTACK_EOF' > /app/round2_attack.c
/*
 * round2_attack.c — Oracle Cloning Attack on Round2 KEM
 *
 * Exploits missing domain separation in Round2's CCA-KEM hash chain:
 *   l   = H(m || pk)
 *   g   = H(l)             <-- included in the ciphertext!
 *   rho = H(g)             <-- the encryption coins
 *
 * Since g is in the ciphertext, an attacker computes rho = H(g) to recover
 * the encryption coins, then performs randomness-based decryption to recover
 * the message m and ultimately the shared secret K — without the secret key.
 *
 * Reference: "Separate Your Domains: NIST PQC KEMs, Oracle Cloning and
 *   Read-Only Indifferentiability" by Bellare, Davis, Gunther (Section 2.3).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "api.h"
#include "pst_api.h"
#include "pst_encrypt.h"
#include "pack.h"
#include "hash.h"
#include "misc.h"
#include "parameters.h"

#define RESPONSE_BUF_SIZE 8192
#define HEX_BUF_SIZE 4096
#define SERVER_URL "http://game_controller:8000"

/* ── Hex helpers ──────────────────────────────────────────────────────── */

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

static void bytes_to_hex(const unsigned char *data, size_t len, char *out) {
    int off = sprintf(out, "0x");
    for (size_t i = 0; i < len; i++)
        off += sprintf(out + off, "%02x", data[i]);
}

/* ── HTTP helper ──────────────────────────────────────────────────────── */

static char response_buf[RESPONSE_BUF_SIZE];

static char *curl_post(const char *url, const char *json_data) {
    char command[RESPONSE_BUF_SIZE];
    snprintf(command, sizeof(command),
        "curl -s -X POST '%s' -H 'Content-Type: application/json' -d '%s'",
        url, json_data);
    FILE *fp = popen(command, "r");
    if (!fp) { fprintf(stderr, "popen failed\n"); return NULL; }
    size_t n = fread(response_buf, 1, sizeof(response_buf) - 1, fp);
    response_buf[n] = '\0';
    int rc = pclose(fp);
    if (rc != 0) fprintf(stderr, "curl exited with %d\n", rc);
    return response_buf;
}

/* Extract a JSON string value by key (simple, non-nested parser). */
static int json_extract(const char *json, const char *key, char *out, size_t out_size) {
    char search[256];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *pos = strstr(json, search);
    if (!pos) return -1;

    /* Skip past the key and find the colon */
    pos += strlen(search);
    pos = strchr(pos, ':');
    if (!pos) return -1;
    pos++; /* skip ':' */

    /* Skip whitespace */
    while (*pos == ' ' || *pos == '\t' || *pos == '\n') pos++;

    if (*pos != '"') return -1;
    pos++; /* skip opening quote */

    size_t i = 0;
    while (*pos && *pos != '"' && i < out_size - 1)
        out[i++] = *pos++;
    out[i] = '\0';
    return 0;
}

/* ── Randomness-based decryption ──────────────────────────────────────── */

static int decrypt_with_rho(unsigned char *m, const unsigned char *ct,
                            const unsigned char *rho, const unsigned char *pk,
                            const parameters *params) {
    size_t len_u = (size_t)(params->d * params->m_bar);
    size_t mu = (size_t)(params->ss_size * 8 / params->B);

    /* Encrypt m=0 with the same rho */
    unsigned char *zero_m = calloc(params->ss_size, 1);
    unsigned char *ct_zero = checked_malloc(params->ct_size);
    encrypt_rho(ct_zero, zero_m, rho, pk, params);

    /* Unpack v from both ciphertexts */
    uint16_t *U_real = checked_malloc(len_u * sizeof(*U_real));
    uint16_t *v_real = checked_malloc(mu * sizeof(*v_real));
    uint16_t *U_zero = checked_malloc(len_u * sizeof(*U_zero));
    uint16_t *v_zero = checked_malloc(mu * sizeof(*v_zero));

    unpack_ct(U_real, v_real, ct, len_u, params->p_bits, mu, params->t_bits);
    unpack_ct(U_zero, v_zero, ct_zero, len_u, params->p_bits, mu, params->t_bits);

    /* v_real - v_zero = encode(m) in t_bits space */
    uint16_t t_mask = (uint16_t)((1 << params->t_bits) - 1);
    uint16_t *msg_encoded = checked_malloc(mu * sizeof(*msg_encoded));
    for (size_t i = 0; i < mu; i++)
        msg_encoded[i] = (uint16_t)((v_real[i] - v_zero[i]) & t_mask);

    /* Extract message bits */
    int shift = params->t_bits - params->B;
    uint16_t b_mask = (uint16_t)((1 << params->B) - 1);
    size_t msg_len = BITS_TO_BYTES(mu * (size_t)params->B);
    memset(m, 0, msg_len);
    for (size_t i = 0; i < mu; i++) {
        uint16_t m_chunk = (uint16_t)((msg_encoded[i] >> shift) & b_mask);
        int idx_bit = params->B * (int)i;
        int idx_byte = idx_bit / 8;
        int bit_shift = idx_bit % 8;
        m[idx_byte] = (unsigned char)(m[idx_byte] | (m_chunk << bit_shift));
    }

    free(zero_m); free(ct_zero);
    free(U_real); free(v_real); free(U_zero); free(v_zero);
    free(msg_encoded);
    return 0;
}

/* ── Main attack ──────────────────────────────────────────────────────── */

int main(void) {
    parameters params;
    if (set_parameters_from_api(&params)) {
        fprintf(stderr, "Failed to set parameters\n");
        return 1;
    }

    size_t cca_ct_size = (size_t)params.ct_size + params.ss_size;

    printf("=== Round2 Oracle Cloning Attack ===\n");
    printf("ss_size=%u, pk_size=%u, ct_size=%u, cca_ct_size=%zu\n",
           params.ss_size, params.pk_size, params.ct_size, cca_ct_size);

    /* Stage 0: Get public key and encapsulation */
    printf("\nStage 0: Getting public key and encapsulation...\n");
    char *resp = curl_post(SERVER_URL "/execute_current_stage",
                           "{\"stage_payload\": {}}");
    if (!resp) { fprintf(stderr, "Stage 0 request failed\n"); return 1; }

    char pk_hex[HEX_BUF_SIZE], ct_hex[HEX_BUF_SIZE];
    if (json_extract(resp, "public_key", pk_hex, sizeof(pk_hex)) != 0) {
        fprintf(stderr, "Failed to extract public_key from: %s\n", resp);
        return 1;
    }
    if (json_extract(resp, "encapsulation", ct_hex, sizeof(ct_hex)) != 0) {
        fprintf(stderr, "Failed to extract encapsulation from: %s\n", resp);
        return 1;
    }

    printf("Public key: %.40s...\n", pk_hex);
    printf("Encapsulation: %.40s...\n", ct_hex);

    /* Parse hex to bytes */
    unsigned char *pk = checked_malloc(params.pk_size);
    unsigned char *ct = checked_malloc(cca_ct_size);

    if (parse_hex(pk_hex, pk, params.pk_size) != (int)params.pk_size) {
        fprintf(stderr, "Public key parse error (expected %u bytes)\n", params.pk_size);
        return 1;
    }
    if (parse_hex(ct_hex, ct, cca_ct_size) != (int)cca_ct_size) {
        fprintf(stderr, "Encapsulation parse error (expected %zu bytes)\n", cca_ct_size);
        return 1;
    }

    /* ---- ATTACK (uses only pk and ct, NOT sk) ---- */
    printf("\n--- Running oracle cloning attack ---\n");

    /* Step 1: Extract g from ciphertext (last ss_size bytes) */
    unsigned char *g = ct + params.ct_size;

    /* Step 2: Compute rho = H(g) — the encryption coins */
    unsigned char *rho = checked_malloc(params.ss_size);
    hash(rho, g, params.ss_size, params.ss_size);

    /* Step 3: Randomness-based decryption to recover m */
    unsigned char *recovered_m = checked_malloc(params.ss_size);
    decrypt_with_rho(recovered_m, ct, rho, pk, &params);

    /* Step 4: Recompute hash chain to get shared secret K */
    /* l = H(m || pk) */
    size_t input_len = params.ss_size + params.pk_size;
    unsigned char *hash_input = checked_malloc(input_len);
    unsigned char *l = checked_malloc(params.ss_size);
    memcpy(hash_input, recovered_m, params.ss_size);
    memcpy(hash_input + params.ss_size, pk, params.pk_size);
    hash(l, hash_input, input_len, params.ss_size);

    /* K = H(l || ct) */
    size_t k_input_len = params.ss_size + cca_ct_size;
    hash_input = checked_realloc(hash_input, k_input_len);
    memcpy(hash_input, l, params.ss_size);
    memcpy(hash_input + params.ss_size, ct, cca_ct_size);

    unsigned char *recovered_ss = checked_malloc(params.ss_size);
    hash(recovered_ss, hash_input, k_input_len, params.ss_size);

    /* Format as hex */
    char ss_hex[256];
    bytes_to_hex(recovered_ss, params.ss_size, ss_hex);
    printf("Recovered shared secret: %s\n", ss_hex);

    /* Stage 1: Submit recovered shared secret */
    printf("\nStage 1: Submitting recovered shared secret...\n");
    char payload[1024];
    snprintf(payload, sizeof(payload),
        "{\"stage_payload\": {\"recovered_shared_secret\": \"%s\"}}", ss_hex);
    resp = curl_post(SERVER_URL "/execute_current_stage", payload);
    printf("Response: %s\n", resp ? resp : "(null)");

    if (resp && strstr(resp, "Yes"))
        printf("\nSUCCESS: Shared secret recovered!\n");
    else
        printf("\nFAILURE: Shared secret recovery failed.\n");

    /* Cleanup */
    free(pk); free(ct); free(rho); free(recovered_m);
    free(hash_input); free(l); free(recovered_ss);

    return 0;
}
ATTACK_EOF

# Compile the attack, linking against the Round2 library sources
echo "Compiling attack..."
cd /app/algorithm_src
gcc -O2 -fcommon -o /app/round2_attack \
    /app/round2_attack.c \
    cca_encrypt.c cca_kem.c cpa_kem.c drng.c hash.c misc.c pack.c \
    parameters.c pst_core.c pst_dem.c pst_encrypt.c rng.c \
    -I. -lssl -lcrypto -lkeccak -L/usr/local/lib

echo "Compilation successful."

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
/app/round2_attack
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
