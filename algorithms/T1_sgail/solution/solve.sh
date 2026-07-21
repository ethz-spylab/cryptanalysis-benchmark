#!/bin/bash

# Write the attack script that submits two colliding plaintexts to the HashCollisionGame.
#
# The Sgail hash function has a vulnerability where swapping the first and second
# halves of an input block (each 256 bytes) produces the same hash digest.
#
# Collision pair:
#   plaintext1: 512 bytes, all zeros except byte[0]=0x01, byte[256]=0x02
#   plaintext2: 512 bytes, all zeros except byte[0]=0x02, byte[256]=0x01

cat <<'PYEOF' > /app/attack.py
import subprocess
import json
import sys

SERVER_URL = "http://game_controller:8000"

# Construct the two colliding plaintexts (512 bytes each).
# Sgail processes input in 512-byte blocks. Swapping the first 256 bytes
# with the second 256 bytes of a block yields the same hash.
plaintext1 = "0x" + "01" + "00" * 255 + "02" + "00" * 255
plaintext2 = "0x" + "02" + "00" * 255 + "01" + "00" * 255

# Optionally verify via the hash oracle that the collision holds
for label, pt in [("plaintext1", plaintext1), ("plaintext2", plaintext2)]:
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", f"{SERVER_URL}/oracle_query",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"oracle_type": "hash", "arguments": {"plaintext": pt}})],
        capture_output=True, text=True
    )
    print(f"{label} hash oracle response: {result.stdout.strip()}")

# Submit the collision to the game
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

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "HashCollisionGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
