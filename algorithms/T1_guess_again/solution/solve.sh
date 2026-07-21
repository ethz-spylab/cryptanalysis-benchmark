#!/bin/bash

# Write the Python attack script
cat <<'EOF' > /app/attack.py
#!/usr/bin/env python3
import binascii
import json
import struct
import subprocess
import sys

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
        print(f"curl error: {result.stderr}", file=sys.stderr)
        raise RuntimeError(f"curl failed: {result.stderr}")
    return json.loads(result.stdout)


def recover_bit(ct, bit):
    assert bit < len(ct) // 4000
    ts = [
        struct.unpack("BB", ct[i : i + 2])
        for i in range(4000 * bit, 4000 * (bit + 1), 2)
    ]
    xs = [a for a, b in ts if b == 1]
    ys = [a for a, b in ts if b == 2]
    return sum(xs) / len(xs) >= sum(ys) / len(ys)


def decrypt(ct):
    num_bits = len(ct) // 4000
    res = sum(recover_bit(ct, b) << b for b in range(num_bits))
    return int.to_bytes(res, num_bits // 8, "little")


# Stage 0: Get the challenge ciphertext
print("Stage 0: Getting challenge ciphertext...")
response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {}}
)
print(f"Stage 0 response keys: {list(response.get('stage_result', {}).keys())}")

challenge_ciphertext_hex = response["stage_result"]["challenge ciphertext"]
print(f"Challenge ciphertext (hex): {challenge_ciphertext_hex[:80]}...")

# Parse the hex ciphertext into bytes
if challenge_ciphertext_hex.startswith("0x") or challenge_ciphertext_hex.startswith("0X"):
    ct_hex_str = challenge_ciphertext_hex[2:]
else:
    ct_hex_str = challenge_ciphertext_hex
ct_bytes = binascii.unhexlify(ct_hex_str)
print(f"Ciphertext length: {len(ct_bytes)} bytes")

# Decrypt using the statistical attack
print("Decrypting...")
recovered_plaintext = decrypt(ct_bytes)
recovered_plaintext_hex = "0x" + binascii.hexlify(recovered_plaintext).decode()
print(f"Recovered plaintext (hex): {recovered_plaintext_hex}")

# Stage 1: Submit the recovered plaintext
print("Stage 1: Submitting recovered plaintext...")
response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {"recovered_plaintext": recovered_plaintext_hex}}
)
print(f"Stage 1 response: {response}")

if response.get("stage_result", {}).get("Game won") == "Yes":
    print("SUCCESS: Plaintext recovered correctly!")
else:
    print("FAILURE: Plaintext recovery failed!")
    sys.exit(1)
EOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
uv run /app/attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AsymmetricDecryptionWithoutAnyKeysGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
