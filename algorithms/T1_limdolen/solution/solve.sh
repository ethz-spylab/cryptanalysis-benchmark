#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/limdolen_attack.py
#!/usr/bin/env python3
"""
Limdolen 128 AEAD tag forgery attack for the AEADTagForgeryGame.

Limdolen's makeTag function processes AD+message blocks by alternating XOR
with `alpha` and `alphaX` (derived from the nonce-based AD key). When the AD
consists of a repeating 2-block (32-byte) pattern, pairs of identical blocks
produce identical round-function outputs that cancel via XOR. This means:

  tag(msg, ad_4blocks) == tag(msg, ad_8blocks)

when ad is a repeating 2-block pattern (ad[0..31] repeated).

Attack strategy:
  1. Construct AD as a 32-byte pattern repeated: ad_short (64 bytes = 4 blocks)
     and ad_long (128 bytes = 8 blocks of the same repeating pattern).
  2. Query the encrypt oracle with (message, nonce, ad_short).
  3. Submit the resulting ciphertext with (nonce, ad_long).
  4. Decryption succeeds because the tags are identical, and the
     (plaintext, nonce, ad_long) triple was never queried.
"""

import json
import os
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"

BLOCK_SIZE = 16  # Limdolen uses 128-bit (16-byte) blocks


def http_post(url, data):
    """POST JSON and return parsed JSON response."""
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main():
    # Construct a 32-byte AD pattern (2 blocks) and repeat it
    # Use a simple deterministic pattern
    ad_block_a = bytes(range(0x10, 0x20))       # 16 bytes
    ad_block_b = bytes(range(0x30, 0x40))       # 16 bytes
    ad_pattern = ad_block_a + ad_block_b        # 32 bytes

    ad_short = ad_pattern * 2                   # 64 bytes = 4 blocks
    ad_long = ad_pattern * 4                    # 128 bytes = 8 blocks

    ad_short_hex = "0x" + ad_short.hex()
    ad_long_hex = "0x" + ad_long.hex()

    # Use a simple message (16 bytes = 1 block)
    message = bytes(range(0x50, 0x60))
    message_hex = "0x" + message.hex()

    # Use a simple nonce (16 bytes for Limdolen)
    nonce = bytes(range(0xA0, 0xB0))
    nonce_hex = "0x" + nonce.hex()

    # ================================================================
    # Step 1: Query the encryption oracle with (message, nonce, ad_short)
    # ================================================================
    print("Step 1: Querying encryption oracle...")
    print(f"  message: {message_hex}")
    print(f"  nonce:   {nonce_hex}")
    print(f"  ad:      {ad_short_hex} ({len(ad_short)} bytes)")

    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": message_hex,
                "nonce": nonce_hex,
                "ad": ad_short_hex,
            },
        },
    )
    print(f"  Oracle result: {result}")

    ciphertext_hex = result["oracle_result"]["ciphertext"]
    print(f"  Ciphertext: {ciphertext_hex}")

    # ================================================================
    # Step 2: Submit the forgery with (ciphertext, nonce, ad_long)
    # ================================================================
    print("\nStep 2: Submitting forgery with different AD...")
    print(f"  ciphertext: {ciphertext_hex}")
    print(f"  nonce:      {nonce_hex}")
    print(f"  ad:         {ad_long_hex} ({len(ad_long)} bytes)")

    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": ciphertext_hex,
                "nonce": nonce_hex,
                "ad": ad_long_hex,
            }
        },
    )
    print(f"\n  Response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: Tag forgery succeeded!")
    else:
        print("\nFAILURE: Forgery was rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/limdolen_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
