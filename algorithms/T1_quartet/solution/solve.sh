#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/quartet_attack.py
#!/usr/bin/env python3
"""
Quartet (Quartet128v1) AEAD tag forgery for the AEADTagForgeryGame.

Mechanism (Mege, OFFICIAL COMMENT: Quartet, 2019-06-10)
-------------------------------------------------------
The Quartet reference implementation still applies its incomplete-final-block
padding `load[rem] ^= 0x01` whenever the message length is not a multiple of 8.
This makes two DISTINCT plaintexts reach an IDENTICAL internal state right after
message absorption, hence produce an IDENTICAL tag:

    P1 = tail                              (rem bytes, 1<=rem<=7: an incomplete block)
    P2 = bytes(load), where               (the 8-byte full block that P1's padding
        load[rem-1-j] = tail[j] (j<rem)    absorbs into state[0] as load64(load))
        load[rem]   ^= 0x01

This collision is KEY- and NONCE-INDEPENDENT: it needs no knowledge of the secret
key, so it works directly in the nonce-respecting, encrypt-only AEAD game.

Forgery (one encrypt query, one deterministic submission)
---------------------------------------------------------
  1. encrypt-query (P2, nonce N, ad="")  ->  CT2 = C2(8 bytes) || tag(16 bytes).
  2. keystream byte ks[j] = C2[j] ^ P2[j]; the never-queried plaintext P1 encrypts
     under the SAME (key, N) to C1[j] = P1[j] ^ ks[j] = P1[j] ^ C2[j] ^ P2[j],
     and shares the identical tag.
  3. Submit (C1 || tag, N, ad="").  It decrypts to P1 with a valid tag, and the
     triple (P1, N, "") was never queried -> a valid AEAD tag forgery.
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


def to_bytes(hex_str):
    if hex_str.startswith("0x") or hex_str.startswith("0X"):
        hex_str = hex_str[2:]
    return bytes.fromhex(hex_str)


def main():
    # Build the universal colliding plaintext pair.
    tail = bytes.fromhex("aabbcc")          # rem = 3; any 1..7-byte tail works
    rem = len(tail)
    load = bytearray(8)
    for j in range(rem):
        load[rem - 1 - j] = tail[j]
    load[rem] ^= 0x01
    P1 = tail                                # incomplete-block plaintext (never queried)
    P2 = bytes(load)                         # full-block plaintext (the queried one)

    nonce_hex = "0x" + "000102030405060708090a0b"

    # Step 1: encrypt oracle query on P2 with empty AD.
    print("Step 1: querying encrypt oracle on P2 =", P2.hex())
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": "0x" + P2.hex(),
                "nonce": nonce_hex,
                "ad": "0x",
            },
        },
    )
    print("  oracle result:", result)
    ct2 = to_bytes(result["oracle_result"]["ciphertext"])
    C2, tag = ct2[:8], ct2[8:]

    # Step 2: deterministically construct the forged ciphertext for P1.
    C1 = bytes(P1[j] ^ C2[j] ^ P2[j] for j in range(rem))
    forged = "0x" + (C1 + tag).hex()
    print("Step 2: submitting forged ciphertext", forged, "(decrypts to P1 =", P1.hex() + ")")

    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": forged,
                "nonce": nonce_hex,
                "ad": "0x",
            }
        },
    )
    print("  response:", response)

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("SUCCESS: Quartet tag forgery succeeded!")
    else:
        print("FAILURE: forgery rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/quartet_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
