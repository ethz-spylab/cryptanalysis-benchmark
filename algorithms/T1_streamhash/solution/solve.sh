#!/bin/bash

# Write the attack script that submits two colliding plaintexts to the HashCollisionGame.
#
# StreamHash absorbs the message one byte at a time with the per-byte state update
#   tabval[i] ^= sbox32[(tabval[i] ^ b ^ i) & 0xff]
# For zero input bytes (b = 0x00) starting from the all-zero initial state, the
# iterated map is periodic with period 40 (Bjorstad, NIST hash-forum 2008-12-11).
# Therefore any two all-zero messages whose lengths differ by a multiple of 40 bytes
# collide. We use 22 zero bytes vs 62 zero bytes (62 - 22 = 40), the exact pair from
# Bjorstad's report; both hash to
#   0x73e9a640d572120b23c2cf861c3f45a9d698ec674d02f3ccde56bc8db2698277.

cat <<'PYEOF' > /app/attack.py
import subprocess
import json
import sys

SERVER_URL = "http://game_controller:8000"

# Two distinct all-zero messages whose lengths differ by one 40-byte cycle.
plaintext1 = "0x" + "00" * 22
plaintext2 = "0x" + "00" * 62

# Optionally verify via the hash oracle that the collision holds.
for label, pt in [("plaintext1", plaintext1), ("plaintext2", plaintext2)]:
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", f"{SERVER_URL}/oracle_query",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"oracle_type": "hash", "arguments": {"plaintext": pt}})],
        capture_output=True, text=True
    )
    print(f"{label} hash oracle response: {result.stdout.strip()}")

# Submit the collision to the game.
print("\nSubmitting collision to HashCollisionGame...")
result = subprocess.run(
    ["curl", "-s", "-X", "POST", f"{SERVER_URL}/execute_current_stage",
     "-H", "Content-Type: application/json",
     "-d", json.dumps({"stage_payload": {"plaintext1": plaintext1, "plaintext2": plaintext2}})],
    capture_output=True, text=True
)
print(f"Game response: {result.stdout.strip()}")

response = json.loads(result.stdout)
if response.get("stage_result", {}).get("Game won") == "Yes":
    print("SUCCESS: Hash collision found!")
else:
    print("FAILURE: Collision was not accepted.")
    sys.exit(1)
PYEOF

# Write the attack launcher script.
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice.
echo "HashCollisionGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
