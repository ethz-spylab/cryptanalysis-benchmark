#!/bin/bash

cat <<'EOF' > /app/feal_attack.c
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define MAX_CHOSEN_PAIRS 12
#define BUFFER_SIZE 2048

uint32_t recovered_subkeys[6];

// Core FEAL functions
uint8_t rotl2(uint8_t a) { return ((a << 2) | (a >> 6)); }

uint32_t leftHalf(uint64_t a) { return (uint32_t)(a >> 32); }
uint32_t rightHalf(uint64_t a) { return (uint32_t)(a & 0xFFFFFFFF); }
uint8_t sepByte(uint32_t a, uint8_t index) {
  return (uint8_t)(a >> (8 * index));
}

uint32_t combineBytes(uint8_t b3, uint8_t b2, uint8_t b1, uint8_t b0) {
  return ((uint32_t)b3 << 24) | ((uint32_t)b2 << 16) | ((uint32_t)b1 << 8) |
         (uint32_t)b0;
}

uint64_t combineHalves(uint32_t leftHalf, uint32_t rightHalf) {
  return (((uint64_t)leftHalf) << 32) | ((uint64_t)rightHalf);
}

uint8_t gBox(uint8_t a, uint8_t b, uint8_t mode) { return rotl2(a + b + mode); }

uint32_t fBox(uint32_t plain) {
  uint8_t x0 = sepByte(plain, 0);
  uint8_t x1 = sepByte(plain, 1);
  uint8_t x2 = sepByte(plain, 2);
  uint8_t x3 = sepByte(plain, 3);

  uint8_t t0 = (x2 ^ x3);
  uint8_t y1 = gBox(x0 ^ x1, t0, 1);
  uint8_t y0 = gBox(x0, y1, 0);
  uint8_t y2 = gBox(t0, y1, 0);
  uint8_t y3 = gBox(x3, y2, 1);

  return combineBytes(y3, y2, y1, y0);
}

// Oracle communication using game session helper
uint64_t oracle_encrypt(uint64_t plaintext) {
  char command[512];
  char hex_plaintext[32];
  char response[BUFFER_SIZE];
  FILE *fp;

  // Format plaintext as hex
  snprintf(hex_plaintext, sizeof(hex_plaintext), "0x%016" PRIx64, plaintext);

  // Use game session helper to query oracle
  snprintf(command, sizeof(command),
           "uv run /app/game_controller_client.py --action oracle_query "
           "--json '{\"oracle_type\": \"encrypt\", \"arguments\": {\"plaintext\": \"%s\"}}'",
           hex_plaintext);

  fp = popen(command, "r");
  if (!fp) {
    fprintf(stderr, "Failed to execute oracle query command\n");
    exit(1);
  }

  // Read response
  size_t bytes_read = fread(response, 1, sizeof(response) - 1, fp);
  response[bytes_read] = '\0';

  int exit_code = pclose(fp);
  if (exit_code != 0) {
    fprintf(stderr, "Oracle query failed with exit code %d: %s\n", exit_code,
            response);
    exit(1);
  }

  // Parse response - the game_controller_client.py returns JSON for oracle queries
  // e.g., {"ciphertext": "0x3bb45355b6ae35ad"}
  // Find the ciphertext value in the JSON response
  char *ct_key = strstr(response, "\"ciphertext\"");
  if (!ct_key) {
    fprintf(stderr, "Failed to find 'ciphertext' in oracle response: %s\n",
            response);
    exit(1);
  }

  // Find the hex value after the key
  char *hex_start = strstr(ct_key, "0x");
  if (!hex_start) {
    // Try without 0x prefix
    hex_start = strchr(ct_key, ':');
    if (hex_start) hex_start++; // skip ':'
    while (hex_start && (*hex_start == ' ' || *hex_start == '"')) hex_start++;
  }

  if (!hex_start) {
    fprintf(stderr, "Failed to find hex value in oracle response: %s\n",
            response);
    exit(1);
  }

  uint64_t ciphertext = 0;
  if (sscanf(hex_start, "%" SCNx64, &ciphertext) != 1) {
    fprintf(stderr, "Failed to parse ciphertext from oracle response: %s\n",
            hex_start);
    exit(1);
  }

  return ciphertext;
}

// Differential cryptanalysis attack globals
int numPlain;
uint64_t plain0[MAX_CHOSEN_PAIRS];
uint64_t cipher0[MAX_CHOSEN_PAIRS];
uint64_t plain1[MAX_CHOSEN_PAIRS];
uint64_t cipher1[MAX_CHOSEN_PAIRS];

void undoFinalOperation() {
  for (int c = 0; c < numPlain; c++) {
    uint32_t cipherLeft0 = leftHalf(cipher0[c]);
    uint32_t cipherRight0 = rightHalf(cipher0[c]) ^ cipherLeft0;
    uint32_t cipherLeft1 = leftHalf(cipher1[c]);
    uint32_t cipherRight1 = rightHalf(cipher1[c]) ^ cipherLeft1;

    cipher0[c] = combineHalves(cipherLeft0, cipherRight0);
    cipher1[c] = combineHalves(cipherLeft1, cipherRight1);
  }
}

uint32_t crackLastRound(uint32_t outdiff) {
  printf("  Using output differential of 0x%08" PRIx32 "\n", outdiff);
  printf("  Cracking...");
  fflush(stdout);

  for (uint32_t fakeK = 0; fakeK < 0xFFFFFFFF; fakeK++) {
    int score = 0;

    // Progress indicator for long searches
    if (fakeK % 0x1000000 == 0) {
      printf(".");
      fflush(stdout);
    }

    for (int c = 0; c < numPlain; c++) {
      uint32_t cipherLeft = leftHalf(cipher0[c]) ^ leftHalf(cipher1[c]);
      uint32_t cipherRight = rightHalf(cipher0[c]) ^ rightHalf(cipher1[c]);

      uint32_t Y = cipherRight;
      uint32_t Z = cipherLeft ^ outdiff;

      uint32_t Y0 = rightHalf(cipher0[c]);
      uint32_t Y1 = rightHalf(cipher1[c]);

      uint32_t fakeInput0 = Y0 ^ fakeK;
      uint32_t fakeInput1 = Y1 ^ fakeK;
      uint32_t fakeOut0 = fBox(fakeInput0);
      uint32_t fakeOut1 = fBox(fakeInput1);
      uint32_t fakeDiff = fakeOut0 ^ fakeOut1;

      if (fakeDiff == Z)
        score++;
      else
        break;
    }

    if (score == numPlain) {
      printf("found subkey : 0x%08" PRIx32 "\n", fakeK);
      return fakeK;
    }
  }

  printf("failed\n");
  return 0;
}

void chosenPlaintext(uint64_t diff) {
  printf("  Generating %i chosen-plaintext pairs\n", numPlain);
  printf("  Using input differential of 0x%016" PRIx64 "\n", diff);

  srand(time(NULL));

  for (int c = 0; c < numPlain; c++) {
    plain0[c] = ((uint64_t)(rand() & 0xFFFF) << 48) |
                ((uint64_t)(rand() & 0xFFFF) << 32) |
                ((uint64_t)(rand() & 0xFFFF) << 16) |
                ((uint64_t)(rand() & 0xFFFF));

    cipher0[c] = oracle_encrypt(plain0[c]);
    plain1[c] = plain0[c] ^ diff;
    cipher1[c] = oracle_encrypt(plain1[c]);

    // Progress indicator
    if (c % 3 == 2) {
      printf("    Generated pair %d/%d\n", c + 1, numPlain);
    }
  }
}

void undoLastRound(uint32_t crackedSubkey) {
  for (int c = 0; c < numPlain; c++) {
    uint32_t cipherLeft0 = leftHalf(cipher0[c]);
    uint32_t cipherRight0 = rightHalf(cipher0[c]);
    uint32_t cipherLeft1 = leftHalf(cipher1[c]);
    uint32_t cipherRight1 = rightHalf(cipher1[c]);

    cipherLeft0 = cipherRight0;
    cipherLeft1 = cipherRight1;
    cipherRight0 = fBox(cipherLeft0 ^ crackedSubkey) ^ leftHalf(cipher0[c]);
    cipherRight1 = fBox(cipherLeft1 ^ crackedSubkey) ^ leftHalf(cipher1[c]);

    cipher0[c] = combineHalves(cipherLeft0, cipherRight0);
    cipher1[c] = combineHalves(cipherLeft1, cipherRight1);
  }
}

void perform_attack() {
  numPlain = 12;
  uint64_t inputDiff1 = UINT64_C(0x8080000080800000);
  uint64_t inputDiff2 = UINT64_C(0x0000000080800000);
  uint64_t inputDiff3 = UINT64_C(0x0000000002000000);
  uint32_t outDiff = UINT32_C(0x02000000);

  printf("Starting FEAL-4 Differential Cryptanalysis Attack (Game Session)\n");
  printf(
      "-----------------------------------------------------------------\n\n");

  // ROUND 4
  printf("ROUND 4\n");
  chosenPlaintext(inputDiff1);
  undoFinalOperation();
  recovered_subkeys[3] = crackLastRound(outDiff);

  // ROUND 3
  printf("ROUND 3\n");
  chosenPlaintext(inputDiff2);
  undoFinalOperation();
  undoLastRound(recovered_subkeys[3]);
  recovered_subkeys[2] = crackLastRound(outDiff);

  // ROUND 2
  printf("ROUND 2\n");
  chosenPlaintext(inputDiff3);
  undoFinalOperation();
  undoLastRound(recovered_subkeys[3]);
  undoLastRound(recovered_subkeys[2]);
  recovered_subkeys[1] = crackLastRound(outDiff);

  // ROUND 1
  printf("ROUND 1\n");
  undoLastRound(recovered_subkeys[1]);
  printf("  Cracking...");
  fflush(stdout);

  for (uint32_t guessK0 = 0; guessK0 < 0xFFFFFFFF; guessK0++) {
    uint32_t guessK4 = 0;
    uint32_t guessK5 = 0;

    // Progress indicator
    if (guessK0 % 0x1000000 == 0) {
      printf(".");
      fflush(stdout);
    }

    int valid = 1;
    for (int c = 0; c < numPlain; c++) {
      uint32_t plainLeft0 = leftHalf(plain0[c]);
      uint32_t plainRight0 = rightHalf(plain0[c]);
      uint32_t cipherLeft0 = leftHalf(cipher0[c]);
      uint32_t cipherRight0 = rightHalf(cipher0[c]);

      uint32_t tempy0 = fBox(cipherRight0 ^ guessK0) ^ cipherLeft0;
      if (guessK4 == 0) {
        guessK4 = tempy0 ^ plainLeft0;
        guessK5 = tempy0 ^ cipherRight0 ^ plainRight0;
      } else if (((tempy0 ^ plainLeft0) != guessK4) ||
                 ((tempy0 ^ cipherRight0 ^ plainRight0) != guessK5)) {
        valid = 0;
        break;
      }
    }

    if (valid && guessK4 != 0) {
      recovered_subkeys[0] = guessK0;
      recovered_subkeys[4] = guessK4;
      recovered_subkeys[5] = guessK5;
      printf("found subkeys : 0x%08" PRIx32 "  0x%08" PRIx32 "  0x%08" PRIx32
             "\n",
             guessK0, guessK4, guessK5);
      break;
    }
  }

  printf("\nRecovered subkeys:\n");
  for (int i = 0; i < 6; i++) {
    printf("  Subkey %d: 0x%08" PRIx32 "\n", i, recovered_subkeys[i]);
  }
}

// Submit result to game session
void submit_recovered_key() {
  char command[1024];
  char key_data[256];

  // Format recovered key as K0||K1||K2||K3||K4||K5
  snprintf(key_data, sizeof(key_data),
           "0x%08" PRIx32 "%08" PRIx32 "%08" PRIx32 "%08" PRIx32 "%08" PRIx32
           "%08" PRIx32,
           recovered_subkeys[0], recovered_subkeys[1], recovered_subkeys[2],
           recovered_subkeys[3], recovered_subkeys[4], recovered_subkeys[5]);

  printf("\nFormatted recovered key: %s\n", key_data);

  snprintf(command, sizeof(command),
           "uv run /app/game_controller_client.py --action "
           "execute_current_stage --json '{\"stage_payload\": "
           "{\"recovered_key\": \"%s\"}}'",
           key_data);

  printf("Submitting key to game session...\n");

  FILE *fp = popen(command, "r");
  if (!fp) {
    fprintf(stderr, "Failed to execute submit command\n");
    exit(1);
  }

  char response[BUFFER_SIZE];
  size_t bytes_read = fread(response, 1, sizeof(response) - 1, fp);
  response[bytes_read] = '\0';

  int exit_code = pclose(fp);
  if (exit_code != 0) {
    fprintf(stderr, "Submit failed with exit code %d: %s\n", exit_code,
            response);
    exit(1);
  }

  printf("Submit response: %s\n", response);
}

int main(int argc, char *argv[]) {
  printf("FEAL-4 Game Session Attack\n");
  printf("=========================\n\n");

  // Perform differential cryptanalysis attack
  perform_attack();

  // Submit the recovered key to the game session
  submit_recovered_key();

  return 0;
}
EOF

# Compile the attack program
gcc -O3 /app/feal_attack.c -o /app/feal_attack

# Write the attack script to the file /app/attack.sh
cat <<'EOF' > /app/attack.sh
#!/bin/bash
./feal_attack
EOF
chmod +x /app/attack.sh

# Write the security game choice to the file /app/security_game_choice.txt
echo "SymmetricTargetKeyRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
