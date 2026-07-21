#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/hyena_attack.py
#!/usr/bin/env python3
"""
HYENA_GIFT-128 (round-2 ref) AEAD tag-forgery for AEADTagForgeryGame.

Bug (Mege, ROUND 2 OFFICIAL COMMENT: HYENA, 2020): in Proc_TXT the last-block
mask uses 2^t * Delta instead of the corrected 3^t * Delta, so the Delta for
the last block of a FULL-block message equals the Delta for the last
(incomplete) block of the same message shortened by one block. This Delta
reuse lets us forge from a single encrypt query.

Construction (M = M1 || M2, two full 16-byte blocks, empty AD); halves are
X_l=X[0:8], X_r=X[8:16], trunc drops the last byte of an 8-byte half:
  query  C||T = E(N, A=empty, M1||M2)  (ct blocks C1, C2; tag T)
  Mforge   = (M1_l ^ C1_l ^ C2_l) || trunc(M2_r)          (15 bytes)
  forged C = ( C2_l || trunc(M2_r ^ M1_r ^ C1_r) ) || T   (15 + tag)
  submit forged C under the SAME (N, A=empty); it decrypts to Mforge.

Offline success condition (prob 1/256, checkable before submit because we know
M1, M2 and observe C1):  M1[15] ^ M2[15] ^ C1[15] == 0x01.

Strategy: each encrypt query uses a FRESH random nonce (nonce-respecting).
Loop, varying message+nonce, until the offline condition holds, then submit the
single forged ciphertext. Mforge (15 bytes) differs from the queried M1||M2
(32 bytes) under the same (N, empty AD), so the submitted triple is new.
"""

import json
import os
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"
BLOCK = 16
HALF = 8


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def to_hex(b):
    return "0x" + b.hex()


def from_hex(s):
    s = s[2:] if s.startswith("0x") else s
    return bytes.fromhex(s)


def encrypt(nonce, pt):
    res = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": to_hex(pt),
                "nonce": to_hex(nonce),
                "ad": "0x",
            },
        },
    )
    return from_hex(res["oracle_result"]["ciphertext"])


def lh(b):
    return b[:HALF]


def rh(b):
    return b[HALF:]


def xor(a, b):
    return bytes(x ^ y for x, y in zip(a, b))


def main():
    max_queries = 200000
    for attempt in range(1, max_queries + 1):
        nonce = os.urandom(12)            # fresh nonce per encrypt query
        M = os.urandom(2 * BLOCK)         # M = M1 || M2, two full blocks
        M1, M2 = M[:BLOCK], M[BLOCK:]
        ct = encrypt(nonce, M)
        C, tag = ct[:-16], ct[-16:]
        C1, C2 = C[:BLOCK], C[BLOCK:]

        if (M1[BLOCK - 1] ^ M2[BLOCK - 1] ^ C1[BLOCK - 1]) == 0x01:
            print(f"Offline condition satisfied after {attempt} encrypt queries.")
            break
    else:
        print("FAILURE: offline condition never satisfied.")
        sys.exit(1)

    # Build the forgery.
    M1_l, M1_r = lh(M1), rh(M1)
    M2_r = rh(M2)
    C1_l, C1_r = lh(C1), rh(C1)
    C2_l = lh(C2)

    Mforge = xor(xor(M1_l, C1_l), C2_l) + M2_r[:HALF - 1]
    forged_C = C2_l + xor(xor(M2_r, M1_r), C1_r)[:HALF - 1]
    forged_ct = forged_C + tag

    print(f"  predicted Mforge: {to_hex(Mforge)}")
    print(f"  forged ciphertext: {to_hex(forged_ct)}")
    print(f"  nonce: {to_hex(nonce)}  ad: 0x")

    response = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {
            "stage_payload": {
                "ciphertext": to_hex(forged_ct),
                "nonce": to_hex(nonce),
                "ad": "0x",
            }
        },
    )
    print(f"Response: {response}")

    if response.get("stage_result", {}).get("Game won") == "Yes":
        print("SUCCESS: HYENA tag forgery succeeded!")
    else:
        print("FAILURE: forgery was rejected.")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/hyena_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AEADTagForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
