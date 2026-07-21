#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/hern_attack.py
#!/usr/bin/env python3
"""
HERN (hern128v1) AEAD tag-collision forgery for the AEADTagForgeryGame.

Vulnerability (NIST official comment, Alexandre Mege 2019-07-12, confirmed by
the HERN/HERON team): processing of associated-data/IV bytes (`H_if_step`,
i.e. InitByte) applies one extra `Addb` per bit compared to message-byte
processing (`H_enc_step`, i.e. EncryptByte). When the 8 internal 'b' bits
produced while processing a message byte are all 0, `Addb` is a no-op and a
message byte behaves exactly like a zero init/AD byte. Consequently the tags of

    enc(plaintext=0x00, ad=)      and      enc(plaintext=, ad=0x00)

collide with probability 2^-8 over the nonce.

Single-query collision detector (the AEAD oracle is nonce-respecting, so we get
ONE encrypt query per nonce): in enc(plaintext=0x00, ad=) the produced
ciphertext is `c0 || TAG`, and ciphertext_bit = b ^ plaintext_bit with
plaintext_bit = 0, so the leading byte c0 equals exactly those 8 'b' bits.
Therefore

    c0 == 0x00   <=>   the collision holds for this nonce,

and when it holds, `TAG` (the bare 16-byte tag) is the authentication tag of the
all-zero-init stream. Submitting

    ciphertext = TAG,  nonce = N,  ad = 0x00

decrypts successfully to the EMPTY plaintext. The recovered triple
("", N, "00") was never an encrypt query (we only queried ("00", N, "")), so it
is a valid forgery and wins the game in a single submission.

Strategy:
  1. Repeatedly query the encrypt oracle with plaintext=0x00, ad= (empty), and
     a fresh nonce each time (nonce-respecting search).
  2. Stop when a returned ciphertext begins with byte 0x00 (collision found).
  3. Submit (ciphertext=TAG, nonce=N, ad=0x00) to win.
"""

import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"
MAX_TRIES = 20000  # expected ~256; huge safety margin


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def norm(h):
    h = h.lower()
    if h.startswith("0x"):
        h = h[2:]
    return h


def main():
    print("Searching for a colliding nonce (enc(PT=00, AD=) -> ct starts 00)...")
    for i in range(1, MAX_TRIES + 1):
        nonce_hex = "0x" + format(i, "032x")  # fresh, distinct nonce per query

        result = http_post(
            f"{SERVER_URL}/oracle_query",
            {
                "oracle_type": "encrypt",
                "arguments": {
                    "plaintext": "0x00",
                    "nonce": nonce_hex,
                    "ad": "0x",
                },
            },
        )
        ct = result.get("oracle_result", {}).get("ciphertext")
        if ct is None:
            print(f"Unexpected oracle response: {result}", file=sys.stderr)
            sys.exit(1)

        body = norm(ct)
        # ciphertext = c0 || TAG ; c0 == 00 <=> collision
        if body[:2] == "00":
            tag_hex = "0x" + body[2:]
            print(f"Collision after {i} queries: nonce={nonce_hex} TAG={tag_hex}")

            # Forge: submit the bare TAG with ad=0x00 under the same nonce.
            # Decrypts to empty plaintext; triple ("", nonce, "00") was never queried.
            response = http_post(
                f"{SERVER_URL}/execute_current_stage",
                {
                    "stage_payload": {
                        "ciphertext": tag_hex,
                        "nonce": nonce_hex,
                        "ad": "0x00",
                    }
                },
            )
            print(f"Submission response: {response}")
            if response.get("stage_result", {}).get("Game won") == "Yes":
                print("SUCCESS: HERN tag forgery accepted!")
                return
            else:
                # Extremely unlikely; keep searching for another collision.
                print("Forgery rejected unexpectedly; continuing search...",
                      file=sys.stderr)

    print(f"No collision within {MAX_TRIES} tries.", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/hern_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
