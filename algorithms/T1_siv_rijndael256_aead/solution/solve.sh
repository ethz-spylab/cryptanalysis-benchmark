#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/siv_attack.py
#!/usr/bin/env python3
"""
SIV-Rijndael256-AEAD (sivrijndael256aead128v1) tag forgery for AEADTagForgeryGame.

Mechanism (official comment, Datta/Jha/Nandi 2019): the associated-data
absorption AUTH_AD lacks correct full-vs-partial domain separation for the tag.
A full final AD block A (|A| = STATE_INBYTES = 32 bytes, last byte 0x80) and a
partial AD block A' = A[0:31] drive the SAME internal state forward; the only
difference is a `domain` tweak value that AUTH_MsgNonce uses ONLY when the
message is >= 16 bytes. With a short message (|M| < 16 bytes) that tweak is
never used, so (N, A, M) and (N, A', M) produce an identical (ciphertext, tag).

Attack:
  1. Query encrypt (N, A, M) with A = 0xaa*31 || 0x80 and |M| = 8 bytes.
  2. Submit forgery (ciphertext=C||T, nonce=N, ad=A'=0xaa*31).
  Decryption succeeds (tag matches) and the (plaintext, nonce, A') triple was
  never queried (queried ad was A, not A') -> win.
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
    nonce_hex = "0x" + "00112233445566778899aabbccddeeff"
    # Full 32-byte final AD block, last byte 0x80.
    A_hex = "0x" + "aa" * 31 + "80"
    # Partial 31-byte AD block: pad(A') == A.
    Ap_hex = "0x" + "aa" * 31
    # Short message: 8 bytes (< 16 bytes) so the domain-using branch is skipped.
    message_hex = "0x" + "11" * 8

    print("Step 1: encrypt (N, A, M) ...")
    print(f"  nonce: {nonce_hex}")
    print(f"  ad   : {A_hex}")
    print(f"  msg  : {message_hex}")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": message_hex,
                "nonce": nonce_hex,
                "ad": A_hex,
            },
        },
    )
    print(f"  oracle result: {result}")
    ciphertext_hex = result["oracle_result"]["ciphertext"]
    print(f"  ciphertext||tag: {ciphertext_hex}")

    print("\nStep 2: forge (C, N, A') with the PARTIAL ad ...")
    print(f"  ad': {Ap_hex}")
    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": ciphertext_hex,
                "nonce": nonce_hex,
                "ad": Ap_hex,
            }
        },
    )
    print(f"  response: {response}")

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
python3 /app/siv_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
