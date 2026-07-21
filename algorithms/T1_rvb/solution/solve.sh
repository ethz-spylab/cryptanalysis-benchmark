#!/bin/bash

# Write the Sage attack script
cat <<'EOF' > /app/attack.sage
#!/usr/bin/env sage
import json
import subprocess

SERVER_URL = "http://game_controller:8000"

F = RealField(10**4)

def recover(pk):
    n = len(pk) // 4
    Tx, x = map(F, [s.decode('ascii') for s in pk.split(b'\0')[:2]])

    a = arccos(Tx) / arccos(x)
    b = F(2*pi) / arccos(x)

    # find an integer k such that a + k * b is close to an integer
    B = 10**(2*n)
    M = matrix([[B, 0, round(a*B)], [0, 1, round(b*B)], [0, 0, B]])
    for l in M.LLL().rows():
        if l[0]:
            k = sign(l[0]) * l[1]
            break

    guess = abs(round(a + k * b))

    # brute-force a small range in case we are slightly off
    for d in range(256):
        for s in (-1, +1):
            if abs(cos((guess + s * d) * arccos(x)) - Tx) < 1e-10:
                return guess + s * d


def curl_post(url, data):
    """POST JSON to the game controller and return parsed response."""
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", url,
         "-H", "Content-Type: application/json",
         "-d", json.dumps(data)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"curl error: {result.stderr}")
        raise RuntimeError(f"curl failed: {result.stderr}")
    return json.loads(result.stdout)


# Stage 0: Get the public key
print("Stage 0: Getting public key...")
response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {}}
)
print(f"Stage 0 response: {response}")

public_key_hex = response["stage_result"]["public key"]
print(f"Public key (hex): {public_key_hex[:80]}...")

# Convert hex public key to bytes
if public_key_hex.startswith("0x") or public_key_hex.startswith("0X"):
    pk_hex_str = public_key_hex[2:]
else:
    pk_hex_str = public_key_hex
pk_bytes = bytes.fromhex(pk_hex_str)
n = len(pk_bytes) // 4
pk_to_sk_size = {460: 110, 690: 160, 920: 210}
sk_size = pk_to_sk_size[len(pk_bytes)]
print(f"Parameter n: {n}, CRYPTO_SECRETKEYBYTES: {sk_size}")

# Recover the private key using the lattice attack
print("Recovering private key...")
secret = recover(pk_bytes)
if secret is None:
    print("ERROR: Failed to recover private key!")
    exit(1)
print(f"Recovered secret integer: {secret}")

# Reconstruct the private key in the same hex format as the CLI output.
# The CLI stores the secret key as its ASCII decimal representation,
# null-padded to CRYPTO_SECRETKEYBYTES bytes, then hex-encoded.
sk_ascii = str(int(secret)).encode('ascii')
sk_bytes = sk_ascii + b'\x00' * (sk_size - len(sk_ascii))
recovered_private_key = "0x" + sk_bytes.hex()
print(f"Reconstructed private key (hex): {recovered_private_key[:80]}...")

# Stage 1: Submit the recovered private key
print("Stage 1: Submitting recovered private key...")
response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {"recovered_private_key": recovered_private_key}}
)
print(f"Stage 1 response: {response}")

if response.get("stage_result", {}).get("Game won") == "Yes":
    print("SUCCESS: Private key recovered correctly!")
else:
    print("FAILURE: Private key recovery failed!")
EOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
sage /app/attack.sage
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "KEMPrivateKeyRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
