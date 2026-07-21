#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/simple_attack.py
#!/usr/bin/env python3
"""
SIMPLE (NIST-LWC round 1, variant simple64gift) AEAD tag forgery for the
AEADTagForgeryGame.

Vulnerability (OFFICIAL COMMENT, A. Mege, 2019): SIMPLE provides NO domain
separation between the associated-data (AD) and plaintext (PT) processing in its
CBC-MAC tag. The tag is computed as

    tag = CBC-MAC_{K_MAC}( pad(PT) || pad(AD) ),   IV = N2

where BOTH regions use the SAME 10* padding (append 0x01 then zero-fill to the
next 8-byte block; a FULL extra block 01 00..00 is added when the length is a
multiple of 8). The CENC keystream covers only the PT bytes and is independent
of AD. Because PT and AD are concatenated into one CBC-MAC stream with identical
padding and no tweak distinguishing them, the PT/AD boundary can be slid: a block
whose value equals the padding pattern can be reinterpreted as PT-pad or AD data.

Forgery (one oracle query, key-independent):
  Query   PT = D8 || (01 00 00 00 00 00 00 00)   (16 bytes),  AD = ""
          absorbed = D8 || [01 00..00]            (msg pad)
                        || [01 00..00]            (ad  pad)
  Forge   PT'= D8                                 (8 bytes),   AD'= 01 00 00 00 00 00 00 00
          absorbed = D8 || [01 00..00]            (msg pad)
                        || [01 00..00]            (ad  data + its pad)   == SAME bytes
  => identical tag. The forged ciphertext is the FIRST 8-byte block of the
     original ciphertext (CENC is positional, so C' = C[:8]) plus the SAME tag.
     It decrypts to (PT'=D8, N, AD'=0100000000000000) -- a triple never queried.
"""

import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"

TAG_HEX = 16          # CRYPTO_ABYTES = 8 bytes -> 16 hex chars
NONCE = "00010203040506"            # 7 bytes (CRYPTO_NPUBBYTES)
PAD_BLOCK = "0100000000000000"      # 10* full padding block (8 bytes) as raw data
D8 = "0001020304050607"             # first plaintext block (arbitrary)


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main():
    pt = D8 + PAD_BLOCK     # 16-byte original plaintext
    ad = ""                 # empty AD

    # ---- Step 1: single encryption query (the only recorded triple) ----
    print("Step 1: query encrypt oracle")
    print(f"  PT={pt}  N={NONCE}  AD='{ad}'")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": "0x" + pt,
                "nonce": "0x" + NONCE,
                "ad": "0x" + ad,
            },
        },
    )
    print(f"  oracle_result: {result}")
    ciphertext = result["oracle_result"]["ciphertext"]
    if ciphertext.startswith("0x"):
        ciphertext = ciphertext[2:]
    tag = ciphertext[-TAG_HEX:]
    c0 = ciphertext[:16]            # first 8-byte ciphertext block (16 hex chars)

    # ---- Step 2: forge by sliding the AD/PT boundary ----
    forged_ct = c0 + tag           # truncated ciphertext + SAME tag
    pt2 = D8
    ad2 = PAD_BLOCK
    print("\nStep 2: submit forgery")
    print(f"  PT'={pt2}  N={NONCE}  AD'={ad2}")
    print(f"  forged_ct={forged_ct}")

    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": "0x" + forged_ct,
                "nonce": "0x" + NONCE,
                "ad": "0x" + ad2,
            }
        },
    )
    print(f"\n  response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: tag forgery accepted!")
    else:
        print("\nFAILURE: forgery rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/simple_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
