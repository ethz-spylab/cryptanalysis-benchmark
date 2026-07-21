#!/bin/bash
# FlexAEAD128b064v1 AEAD tag-forgery solution (AEADTagForgeryGame).
#
# Mechanism (probability 1): FlexAEAD's original associated-data padding pads a
# partial final AD block with 0x00 only (Mege, OFFICIAL COMMENT FlexAEAD
# 2019-06-03; Eichlseder/Kales/Schofnegger, eprint 2019/679 §4.1). A partial
# final AD block A and the AD A||00 (one extra zero byte, still inside the same
# 8-byte final block) are zero-extended to the identical block before being
# mixed into the checksum, so they produce the IDENTICAL tag/ciphertext.
#
# Attack: query encrypt(PT, nonce, AD=0x00); the resulting ciphertext also
# authenticates under AD=0x0000 -- an unqueried (plaintext,nonce,ad) triple --
# so it is a valid forgery.

cat <<'PYEOF' > /app/flexaead_attack.py
#!/usr/bin/env python3
"""FlexAEAD128b064v1 AD zero-padding length-extension forgery for AEADTagForgeryGame."""
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
    # 1-block plaintext (64-bit block), fixed nonce, partial 1-byte AD.
    plaintext_hex = "0x0011223344556677"
    nonce_hex = "0x0001020304050607"
    ad_short_hex = "0x00"      # 1-byte partial AD block
    ad_forge_hex = "0x0000"    # zero-extended within the same final block -> same tag

    print("Step 1: encrypt oracle query (AD=0x00)...")
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
    print(f"  Ciphertext: {ciphertext_hex}")

    print("\nStep 2: submit forgery with AD=0x0000 (unqueried triple)...")
    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": ciphertext_hex,
                "nonce": nonce_hex,
                "ad": ad_forge_hex,
            }
        },
    )
    print(f"  Response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: Tag forgery succeeded!")
    else:
        print("\nFAILURE: Forgery was rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/flexaead_attack.py
EOF
chmod +x /app/attack.sh

echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
