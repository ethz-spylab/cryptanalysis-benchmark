#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/clae_attack.py
#!/usr/bin/env python3
"""
CLAE 128 AEAD tag forgery attack for the AEADTagForgeryGame.

CLAE uses a "trivial" padding that simply drops a trailing 0xFF byte for short
messages (this limitation is acknowledged in Section 5 of the CLAE spec and in
the official NIST-LWC comment by A. Mege). Consequently, for any fixed
(key, nonce, ad), the single-byte plaintext PT=0xFF and the EMPTY plaintext
encrypt to the SAME ciphertext/tag.

When that ciphertext is decrypted, crypto_aead_decrypt recovers the EMPTY
plaintext (mlen=0): the 8-byte tag region decodes to all-0xFF and the
trailing-FF stripping loop reduces mlen to 0.

Forgery:
  1. Ask the encrypt oracle for PT=0xFF under (nonce N, empty ad). The game
     records the triple (plaintext="ff", nonce=N, ad="").
  2. Submit that ciphertext with (nonce=N, ad=""). It decrypts to the EMPTY
     plaintext, so the recovered triple is (plaintext="", nonce=N, ad="")
     -- which was NEVER queried to the encrypt oracle.
  => valid AEAD tag forgery, Game won: Yes.

The forgery's nonce repeats the queried nonce, which the game explicitly
permits (the nonce-respecting rule applies to encryption queries only).
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
    # Any fixed 12-byte nonce and empty associated data.
    nonce_hex = "0x731847c05e508e2c6acf0fc2"
    ad_hex = "0x"

    # Step 1: encrypt PT=0xFF. Game records triple ("ff", nonce, "").
    print("Step 1: Querying encryption oracle with PT=0xFF...")
    print(f"  plaintext: 0xff")
    print(f"  nonce:     {nonce_hex}")
    print(f"  ad:        {ad_hex}")

    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": "0xff",
                "nonce": nonce_hex,
                "ad": ad_hex,
            },
        },
    )
    print(f"  Oracle result: {result}")

    ciphertext_hex = result["oracle_result"]["ciphertext"]
    print(f"  Ciphertext: {ciphertext_hex}")

    # Step 2: submit the same ciphertext. It decrypts to the EMPTY plaintext,
    # a triple ("", nonce, "") that was never queried.
    print("\nStep 2: Submitting forgery (decrypts to empty plaintext)...")
    print(f"  ciphertext: {ciphertext_hex}")
    print(f"  nonce:      {nonce_hex}")
    print(f"  ad:         {ad_hex}")

    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": ciphertext_hex,
                "nonce": nonce_hex,
                "ad": ad_hex,
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
python3 /app/clae_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
