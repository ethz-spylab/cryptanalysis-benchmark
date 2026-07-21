#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/cilipadi_attack.py
#!/usr/bin/env python3
"""
CiliPadi-128 v1 "mild" AEAD tag forgery for the AEADTagForgeryGame.

Padding flaw (NIST LWC OFFICIAL COMMENT, Bagheri & Sadeghi 2019): CiliPadi pads
an AD (or message) block only when its length is NOT a multiple of the rate
r = BYTERATE = 8 bytes, by appending 0x80 then zeros. Therefore:

  AD = X        (7 bytes, not a multiple of r) -> padded to X || 0x80
  AD = X || 0x80 (8 bytes, a multiple of r)    -> NOT padded, already X || 0x80

Both feed the IDENTICAL rate block X||0x80 into the sponge, so for the same
key/nonce/plaintext they yield the SAME tag.

Forgery:
  1. Query encrypt(plaintext=M, nonce=N, ad=X)  with X a 7-byte AD and M a
     non-empty plaintext (the AEAD CLI's `encrypt` requires a non-empty plaintext;
     an empty `plaintext:` line is rejected as malformed).
  2. Submit (ciphertext, nonce=N, ad=X||0x80). It decrypts successfully to M, and
     the recovered triple (M, N, X||0x80) was never queried (different ad), so the
     forgery wins. The AD-padding collision is independent of the plaintext, so the
     same ciphertext/tag is valid under both ADs.
"""

import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main():
    # 16-byte nonce, 7-byte AD (one byte short of the 8-byte rate).
    nonce_hex = "0x" + bytes(range(0xA0, 0xB0)).hex()
    ad_short = bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11])  # 7 bytes
    ad_long = ad_short + b"\x80"                                  # 8 bytes
    ad_short_hex = "0x" + ad_short.hex()
    ad_long_hex = "0x" + ad_long.hex()

    # Non-empty 16-byte plaintext (the encrypt CLI rejects an empty plaintext).
    plaintext_hex = "0x" + bytes(range(0x00, 0x10)).hex()

    # Step 1: encrypt the plaintext under the short (padded) AD.
    print("Step 1: Querying encryption oracle (16-byte PT, 7-byte AD)...")
    print(f"  plaintext: {plaintext_hex}")
    print(f"  nonce: {nonce_hex}")
    print(f"  ad:    {ad_short_hex}")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": plaintext_hex,
                "nonce": nonce_hex,
                "ad": ad_short_hex,
            },
        },
    )
    print(f"  Oracle result: {result}")
    ciphertext_hex = result["oracle_result"]["ciphertext"]
    print(f"  Ciphertext (= tag): {ciphertext_hex}")

    # Step 2: replay the same ciphertext/nonce under the 8-byte (unpadded) AD.
    print("\nStep 2: Submitting forgery with X || 0x80 as AD...")
    print(f"  ciphertext: {ciphertext_hex}")
    print(f"  nonce:      {nonce_hex}")
    print(f"  ad:         {ad_long_hex}")
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
python3 /app/cilipadi_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
