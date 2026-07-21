#!/bin/bash

# Bleep64 (NIST-LWC round-1 AEAD) differential tag-forgery for AEADTagForgeryGame.
#
# Mechanism (Dobraunig & Rotella official comment; extended by Bartlett et al.):
#   Bleep64 processes data in 32-bit little-endian words ("blocks"). Ciphertext
#   blocks have an additive (1's/2's-complement) relationship to the keystream.
#   A signed difference +d on an even-indexed ciphertext block can be cancelled
#   by -d on a later even-indexed block, leaving the final state (and thus the
#   8-byte tag) unchanged with probability ~1-2^-31 for d=1. So for a 3-block
#   message C1||C2||C3||T, the tag T is also valid for (C1-1)||C2||(C3+1)||T,
#   which decrypts to a DIFFERENT plaintext triple -> forgery.
#
# Game flow:
#   1. Query encrypt(plaintext=12 random bytes, nonce, ad="") -> C(12)||tag(8).
#   2. Forge: subtract 1 from block 0 and add 1 to block 2 (little-endian),
#      keep the 8-byte tag. Submit (forged_ct, nonce, ad="").
#   3. The forged ciphertext decrypts (same tag) to a plaintext != the queried
#      one, so the (plaintext, nonce, ad) triple was never queried -> Game won.

cat <<'PYEOF' > /app/bleep64_attack.py
#!/usr/bin/env python3
import json
import os
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
    h = h.strip()
    return h[2:] if h.startswith("0x") or h.startswith("0X") else h


def word_add(ct, block_idx, delta):
    """Add delta (mod 2^32) to the little-endian 32-bit block at block_idx."""
    b = bytearray(ct)
    off = block_idx * 4
    w = int.from_bytes(b[off:off + 4], "little")
    w = (w + delta) & 0xFFFFFFFF
    b[off:off + 4] = w.to_bytes(4, "little")
    return bytes(b)


def main():
    # 12-byte (3-block) message, empty AD, a fixed nonce (12 bytes for Bleep64).
    plaintext = os.urandom(12)
    nonce = bytes(range(12))            # 000102...0b
    ad = b""

    pt_hex = "0x" + plaintext.hex()
    nonce_hex = "0x" + nonce.hex()
    ad_hex = "0x" + ad.hex()            # "0x"

    # Step 1: encrypt oracle.
    print("Step 1: querying encrypt oracle...")
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": pt_hex,
                "nonce": nonce_hex,
                "ad": ad_hex,
            },
        },
    )
    print(f"  oracle result: {result}")
    ct_hex = result["oracle_result"]["ciphertext"]
    ct = bytes.fromhex(strip0x(ct_hex))
    # ct = 12 bytes ciphertext (3 blocks) + 8 bytes tag = 20 bytes
    if len(ct) != 20:
        print(f"  unexpected ciphertext length {len(ct)} (expected 20)")
        sys.exit(1)

    # Step 2: differential forgery on the 3 message blocks (tag untouched).
    forged = word_add(ct, 0, -1)   # C1 - 1  (even-indexed block 0)
    forged = word_add(forged, 2, +1)  # C3 + 1  (even-indexed block 2)
    forged_hex = "0x" + forged.hex()
    print(f"\nStep 2: submitting forged ciphertext {forged_hex}")

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
    print(f"\n  response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: Bleep64 tag forgery succeeded!")
    else:
        print("\nFAILURE: forgery was rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/bleep64_attack.py
EOF
chmod +x /app/attack.sh

echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
