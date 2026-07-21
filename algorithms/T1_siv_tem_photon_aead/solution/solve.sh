#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/siv_tem_photon_attack.py
#!/usr/bin/env python3
"""
SIV-TEM-PHOTON-AEAD tag-forgery attack for the AEADTagForgeryGame.

Vulnerability (official LWC comment, Datta/Jha/Nandi 2019): improper associated
-data domain separation in the reference implementation. AD is absorbed in
48-byte chunks (state=32 bytes + tweak=16 bytes). The final chunk is treated as
a FULL block when its length is exactly 48 bytes (last 16 bytes go verbatim into
the tweak, no 0x80 pad), but as a PADDED partial block when its length is 47
bytes (last_tweak[15] = 0x80). Hence:

    A  = (47 arbitrary bytes) || 0x80     (48 bytes, full block, no pad)
    A' = (those same 47 bytes)            (47 bytes, padded to ...||0x80)

absorb to the identical state+tweak. They differ only in a carried domain that
is never used for short messages, so Enc(N, A, M) == Enc(N, A', M) bit-for-bit
(ciphertext and tag). This is a universal forgery for short messages.

Attack:
  1. Query encrypt(nonce, A48, M) with an empty message M.
  2. Submit the returned ciphertext with (nonce, A47).
  3. It decrypts to M; (M, nonce, A47) was never queried (we queried A48). Win.
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
    # Short non-empty message (< 256 bits keeps the domain-sep flaw invisible;
    # the AEAD CLI's encrypt rejects an empty plaintext).
    message_hex = "0xdeadbeef"
    # 16-byte nonce.
    nonce_hex = "0x" + "01".ljust(32, "0")
    # A48: 47 zero bytes followed by 0x80 (full 384-bit AD block, no pad applied).
    a48 = bytes(47) + b"\x80"
    # A47: the same 47 bytes (re-pads to ...||0x80 internally => same state/tweak).
    a47 = bytes(47)
    ad_query_hex = "0x" + a48.hex()
    ad_forge_hex = "0x" + a47.hex()

    print("Step 1: encrypt(nonce, A48, empty message)")
    print(f"  nonce: {nonce_hex}")
    print(f"  ad:    {ad_query_hex} ({len(a48)} bytes)")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": message_hex,
                "nonce": nonce_hex,
                "ad": ad_query_hex,
            },
        },
    )
    print(f"  Oracle result: {result}")
    ciphertext_hex = result["oracle_result"]["ciphertext"]
    print(f"  Ciphertext||tag: {ciphertext_hex}")

    print("\nStep 2: submit forgery with A47 (never queried)")
    print(f"  ad: {ad_forge_hex} ({len(a47)} bytes)")
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
    print(f"\n  Response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: AD-padding tag forgery succeeded!")
    else:
        print("\nFAILURE: Forgery was rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/siv_tem_photon_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
