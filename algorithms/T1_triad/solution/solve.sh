#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/triad_attack.py
#!/usr/bin/env python3
"""
Triad (triadaev1) AEAD tag-forgery attack for the AEADTagForgeryGame.

Triad's MAC absorbs, in order:
    [ AD bytes ] [ 7-byte little-endian adlen ] [ message bytes ]
with NO length encoding or domain-separation tweak for the message. The 7-byte
adlen field is the only AD/PT boundary marker, so any two (AD, PT) pairs whose
absorbed byte-streams are equal produce the SAME tag. This lets us slide the
boundary by relocating the adlen field into a decoy inside the plaintext.

Attack (key-independent, one oracle query):
  1. Encrypt PT=0x08000000000000 (7B), AD=0x00 (1B).
     absorbed stream = 00 | 01 00 00 00 00 00 00 | 08 00 00 00 00 00 00
     -> returns CT1 = C1 || tag (7-byte ciphertext + 8-byte tag).
  2. Forge: take the last 8 bytes of CT1 (the tag) as the entire ciphertext,
     with AD=0x0001000000000000 (8B), PT empty.
     absorbed stream = 00 01 00 00 00 00 00 00 | 08 00 00 00 00 00 00  (identical!)
     -> same tag, empty PT, so the ciphertext IS the tag; decrypt verifies.

The forged (plaintext='', nonce, ad=0x0001000000000000) triple is never the
queried (0x08000000000000, nonce, 0x00) triple, so the game accepts the forgery.
The forgery reuses the encrypt query's nonce (allowed: nonce-respecting applies
to encrypt queries only).
"""

import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"

TAG_BYTES = 8  # CRYPTO_ABYTES for triadaev1


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def strip0x(h):
    h = h.lower()
    return h[2:] if h.startswith("0x") else h


def main():
    nonce_hex = "0x" + "2a2b2c2d2e2f303132333435"   # 12-byte nonce
    # PT first 7 bytes = target adlen (8) as 7-byte LE -> 0x08 00 00 00 00 00 00
    pt_hex = "0x08000000000000"
    ad_query_hex = "0x00"                            # adlen = 1
    ad_forge_hex = "0x0001000000000000"              # adlen = 8

    # ---- Step 1: single encrypt oracle query ----
    print("Step 1: encrypt oracle query")
    print(f"  plaintext: {pt_hex}")
    print(f"  nonce:     {nonce_hex}")
    print(f"  ad:        {ad_query_hex}")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": pt_hex,
                "nonce": nonce_hex,
                "ad": ad_query_hex,
            },
        },
    )
    print(f"  oracle result: {result}")
    ct1_hex = strip0x(result["oracle_result"]["ciphertext"])

    # ---- Step 2: forged ciphertext = last 8 bytes of CT1 (the tag) ----
    forged_ct_hex = "0x" + ct1_hex[-2 * TAG_BYTES:]
    print("\nStep 2: submit forgery")
    print(f"  ciphertext: {forged_ct_hex}")
    print(f"  nonce:      {nonce_hex}")
    print(f"  ad:         {ad_forge_hex}")
    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": forged_ct_hex,
                "nonce": nonce_hex,
                "ad": ad_forge_hex,
            }
        },
    )
    print(f"\n  response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: Triad tag forgery succeeded!")
    else:
        print("\nFAILURE: forgery rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/triad_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
