#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/fountain_attack.py
#!/usr/bin/env python3
"""
Fountain128v1 AEAD tag forgery for the AEADTagForgeryGame.

Mechanism (Mege, "OFFICIAL COMMENT: Fountain", NIST-LWC forum, 2019-06-03):
The Fountain round-1 reference code (caused by LFSR-numbering typos in the
reference implementation) produces a TAG COLLISION when a *middle* byte of the
associated data flips between 0x80 and 0x01, provided the bytes to its left and
right follow the same incremental pattern as the plaintext. The full ciphertext
(C || tag) is byte-identical for the two AD values, so one ciphertext decrypts
successfully under two distinct associated-data strings.

Attack:
  1. Encrypt (PT, nonce, AD_80) via the oracle  -> CT.
  2. Submit (CT, nonce, AD_01) as the forgery.
  3. CT decrypts to PT under AD_01, and the (PT, nonce, AD_01) triple was never
     queried to the encrypt oracle  ->  Game won.

Uses the worked vector from the official comment (Fountain128v1):
  PT    = 000001010202030304040505060607
  AD_80 = ...060607 80 000001...   (0x80 middle byte)
  AD_01 = ...060607 01 000001...   (0x01 middle byte)
"""

import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"

# 12-byte nonce (CRYPTO_NPUBBYTES = 12).
NONCE = "0x000102030405060708090a0b"
PT    = "0x000001010202030304040505060607"
# Two ADs that differ only in the middle byte (0x80 vs 0x01); same surrounding
# incremental pattern as PT on both sides -> identical ciphertext+tag.
AD_80 = "0x00000101020203030404050506060780000001010202030304040505060607"
AD_01 = "0x00000101020203030404050506060701000001010202030304040505060607"


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main():
    print("Step 1: encrypt (PT, nonce, AD with 0x80 middle byte)")
    print(f"  plaintext: {PT}")
    print(f"  nonce:     {NONCE}")
    print(f"  ad:        {AD_80}")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {"plaintext": PT, "nonce": NONCE, "ad": AD_80},
        },
    )
    print(f"  Oracle result: {result}")
    ciphertext_hex = result["oracle_result"]["ciphertext"]
    print(f"  Ciphertext: {ciphertext_hex}")

    print("\nStep 2: submit forgery (same ciphertext, AD with 0x01 middle byte)")
    print(f"  ciphertext: {ciphertext_hex}")
    print(f"  nonce:      {NONCE}")
    print(f"  ad:         {AD_01}")
    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": ciphertext_hex,
                "nonce": NONCE,
                "ad": AD_01,
            }
        },
    )
    print(f"\n  Response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: Fountain tag forgery succeeded!")
    else:
        print("\nFAILURE: Forgery was rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/fountain_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
