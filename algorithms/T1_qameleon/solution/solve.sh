#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/qameleon_attack.py
#!/usr/bin/env python3
"""
Qameleon (qameleon12812864gpv1) AEAD tag forgery for the AEADTagForgeryGame.

Documented prob-1 forgery (NIST LWC official comment, 2019). The tag is

    T = E_{nonce, MSB_CHKSUM, blocknum=0}(Checksum) XOR Auth(AD),
    Checksum = XOR of all (padded) message blocks.

The tag's tweak hard-wires the block number to 0, so the tag depends ONLY on
(nonce, AD, Checksum) -- it is independent of the message length/structure.
Therefore EVERY message whose block-checksum is zero produces the SAME tag,
in particular:

  * M = M1 || M1   (two identical 16-byte blocks)  -> Checksum = M1 ^ M1 = 0
  * the empty message                              -> Checksum = 0

Forgery:
  1. Query encrypt(plaintext = M1||M1, nonce = N, ad = A). From the returned
     ciphertext  [ C-blocks | tag(16) | mlen(8) ]  extract the 16-byte tag
     (the 16 bytes immediately before the trailing 8-byte length field).
  2. Build the empty-message ciphertext  forged = tag || 0x00*8  (mlen = 0),
     a 24-byte value (24 % 16 == 8, the scheme's only valid empty-message
     ciphertext length). Submit (forged, N, A).

The submitted ciphertext decrypts (Checksum = 0 for the empty message, same
nonce/AD) to the EMPTY plaintext, and the triple (plaintext="", N, A) was
never queried to the encrypt oracle (we queried (M1||M1, N, A)), so the
forgery is fresh and wins.
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


def strip0x(h):
    h = h.strip().lower()
    return h[2:] if h.startswith("0x") else h


def main():
    nonce_hex = "0x0011223344556677"          # 8-byte nonce
    ad_hex = "0xa0a1a2a3"                      # associated data
    m1 = "11111111111111111111111111111111"   # 16-byte block
    plaintext_hex = "0x" + m1 + m1            # M1 || M1, checksum = 0

    # Step 1: encrypt M1||M1 to obtain a tag for a checksum-0 message.
    print("Step 1: Querying encryption oracle with plaintext = M1||M1 ...")
    print(f"  plaintext: {plaintext_hex}")
    print(f"  nonce:     {nonce_hex}")
    print(f"  ad:        {ad_hex}")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": plaintext_hex,
                "nonce": nonce_hex,
                "ad": ad_hex,
            },
        },
    )
    print(f"  Oracle result: {result}")
    ct = strip0x(result["oracle_result"]["ciphertext"])

    # Layout: [C-blocks][tag:16 bytes][mlen:8 bytes]. Extract the tag (the 16
    # bytes = 32 hex chars immediately before the trailing 8-byte length field).
    tag = ct[-48:-16]
    forged = tag + "00" * 8        # empty-message ct: tag || mlen(=0)
    forged_hex = "0x" + forged
    print(f"  full ciphertext = 0x{ct}  ({len(ct)//2} bytes)")
    print(f"  extracted tag   = 0x{tag}")
    print(f"  forged ct       = {forged_hex}  ({len(forged)//2} bytes)")

    # Step 2: submit the empty-message forgery under the same nonce / AD.
    print("\nStep 2: Submitting empty-message forgery ...")
    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": forged_hex,
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
python3 /app/qameleon_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
