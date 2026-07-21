#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy the attack library to /app/ (excluding the run_attack call at the end)
# The attack.sage file defines all needed functions: attack(str_pk, str_ct) etc.
# We strip the last two lines which call run_attack(0).
head -n -2 "$SCRIPT_DIR/attack.sage" > /app/attack_lib.sage

# Create the game-interfacing attack script
cat <<'SAGE_EOF' > /app/game_attack.sage
#!/usr/bin/env sage
import json
import subprocess
import sys
import os

sys.path.insert(0, '/app')
os.chdir('/app')

# Load the EdonK attack functions (attack, get_pk, get_ct, etc.)
load('attack_lib.sage')

# ===================================================================
# Game interaction helpers
# ===================================================================
SERVER_URL = "http://game_controller:8000"

def curl_post(url, data):
    """POST JSON to the game controller and return parsed response."""
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", url,
         "-H", "Content-Type: application/json",
         "-d", json.dumps(data)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"curl error: {result.stderr}")
        raise RuntimeError(f"curl failed: {result.stderr}")
    return json.loads(result.stdout)

# ===================================================================
# Stage 0: Get the public key and encapsulation
# ===================================================================
print("\n" + "="*60)
print("Stage 0: Getting public key and encapsulation")
print("="*60)

response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {}}
)
print(f"Response: {response}")

public_key_hex = response["stage_result"]["public_key"]
encapsulation_hex = response["stage_result"]["encapsulation"]
print(f"Public key (hex): {public_key_hex[:80]}...")
print(f"Encapsulation (hex): {encapsulation_hex[:80]}...")

# ===================================================================
# Run the attack
# ===================================================================
# Strip the 0x prefix and convert to uppercase - the attack functions
# expect raw uppercase hex strings (matching the KAT file format).
# The hash comparison inside retrieve_secret() is case-sensitive.
str_pk = public_key_hex
if str_pk.startswith("0x") or str_pk.startswith("0X"):
    str_pk = str_pk[2:]
str_pk = str_pk.upper()

str_ct = encapsulation_hex
if str_ct.startswith("0x") or str_ct.startswith("0X"):
    str_ct = str_ct[2:]
str_ct = str_ct.upper()

print("\n" + "="*60)
print("Running EdonK attack")
print("="*60)

recovered_secret = attack(str_pk, str_ct)
print(f"Recovered shared secret: {recovered_secret}")

if not recovered_secret:
    print("ERROR: Attack failed to recover the shared secret!")
    sys.exit(1)

# Format as 0x-prefixed lowercase hex to match the CLI output format
recovered_shared_secret = "0x" + recovered_secret.lower()
print(f"Formatted shared secret: {recovered_shared_secret}")

# ===================================================================
# Stage 1: Submit the recovered shared secret
# ===================================================================
print("\n" + "="*60)
print("Stage 1: Submitting recovered shared secret")
print("="*60)

response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {"recovered_shared_secret": recovered_shared_secret}}
)
print(f"Response: {response}")

if response.get("stage_result", {}).get("Game won") == "Yes":
    print("\nSUCCESS: Shared secret recovered correctly!")
else:
    print("\nFAILURE: Shared secret recovery failed!")
    sys.exit(1)
SAGE_EOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
cd /app
sage game_attack.sage
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
