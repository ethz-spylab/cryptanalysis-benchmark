#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/sneik_attack.py
#!/usr/bin/env python3
"""
SNEIKEN-128 (SNEIK v1, NIST-LWC round 1) AEAD tag forgery for AEADTagForgeryGame.

Vulnerability (Perrin, ePrint 2019/374 "Probability 1 Iterated Differential
in the SNEIK Permutation"; exploited by Khairallah, ePrint 2019/408 "Forgery
Attack on SNEIKEN"). The SNEIK f512 permutation has a probability-1 iterated
differential: the difference

    DELTA = MSB (bit 31) of every 32-bit little-endian word
          = 0x80 at byte indices 3, 7, 11, ..., 63 of the 64-byte state

maps to itself through the permutation with probability 1 (round constants and
the domain byte are XORed in, so the difference cancels; the rotations are
linear; an MSB difference in both operands of a modular addition is preserved
because the carry out of the MSB is discarded).

SNEIKEN-128 absorbs associated data in FULL-STATE mode (the whole 64-byte
block is XORed before each permutation call). If we add DELTA to one full
64-byte AD block, the state difference becomes DELTA; the permutation preserves
it; adding DELTA to a *second* full AD block cancels it -> the duplex state is
byte-identical afterwards, so the authentication tag is identical. We thus
convert a legitimately-encrypted ciphertext for AD `ad` into a valid forgery
for a DIFFERENT AD `ad'` (same nonce, same ciphertext/tag) without the key.

Strategy:
  1. Query the encrypt oracle once with (message, nonce, ad) where ad is two
     full 64-byte blocks (128 bytes) -> get ciphertext c (= C || tag).
  2. Forge ad' = ad XOR (DELTA on block 0) XOR (DELTA on block 1).
  3. Submit (c, nonce, ad'). It decrypts (tag still valid) and the recovered
     triple (message, nonce, ad') was never queried -> Game won.
"""

import json
import urllib.request

SERVER_URL = "http://game_controller:8000"

# Probability-1 differential: 0x80 on the most-significant byte of every
# little-endian 32-bit word of the 64-byte permutation state.
DELTA = bytes(0x80 if (i % 4) == 3 else 0 for i in range(64))


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main():
    nonce = bytes(range(0xA0, 0xB0))           # 16-byte nonce
    message = bytes(range(0x50, 0x78))          # 40-byte message
    # Two FULL 64-byte AD blocks (128 bytes) so the differential can be
    # injected and cancelled across the two full-state absorptions.
    ad = bytes((i * 7 + 3) & 0xFF for i in range(128))

    nonce_hex = "0x" + nonce.hex()
    message_hex = "0x" + message.hex()
    ad_hex = "0x" + ad.hex()

    # Step 1: legitimate encryption query.
    print("Step 1: encrypt oracle query")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": message_hex,
                "nonce": nonce_hex,
                "ad": ad_hex,
            },
        },
    )
    print(f"  oracle result: {result}")
    ciphertext_hex = result["oracle_result"]["ciphertext"]

    # Step 2: apply the probability-1 differential to BOTH full AD blocks.
    ad_f = bytearray(ad)
    for off in (0, 64):
        for i in range(64):
            ad_f[off + i] ^= DELTA[i]
    ad_f_hex = "0x" + bytes(ad_f).hex()
    assert bytes(ad_f) != ad

    # Step 3: submit the UNCHANGED ciphertext under the forged AD.
    print("Step 2: submit forgery with differential-modified AD")
    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": ciphertext_hex,
                "nonce": nonce_hex,
                "ad": ad_f_hex,
            }
        },
    )
    print(f"  response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("SUCCESS: tag forgery succeeded!")
    else:
        print("FAILURE: forgery rejected.")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/sneik_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
