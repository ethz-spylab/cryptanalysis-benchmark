#!/bin/bash

# Solution for T1_tangle -> HashCollisionGame.
#
# Tangle (SHA-3 Round-1 candidate) is collision-broken (Thomsen, "Untangled", 2008).
# Flipping the MSB of message words 0,1,8,9 propagates through the message expansion
# such that the paired expanded words cancel their differences in C = W[2i]+W[2i+1]
# and again in A+B, yielding a full internal-state collision. For Tangle-256 (the
# CLI default, hashbitlen=256), setting word0 = 0x19c8 and words 1..9 = 0 collides.
#
# Colliding pair (40-byte messages, words stored little-endian):
#   plaintext1 = c8190000 + 36 zero bytes
#   plaintext2 = plaintext1 with the MSB (0x80000000) of words 0,1,8,9 flipped
# Both hash (Tangle-256) to
#   0xf710be651ab67737a58ac452056bbf13e62abed071943617dadbf25c2dea710b

cat <<'PYEOF' > /app/attack.py
import subprocess
import json
import sys

SERVER_URL = "http://game_controller:8000"

# Tangle-256 collision (verified against the reference CLI).
plaintext1 = "0xc8190000000000000000000000000000000000000000000000000000000000000000000000000000"
plaintext2 = "0xc8190080000000800000000000000000000000000000000000000000000000000000008000000080"

# Optionally confirm via the hash oracle that the two plaintexts collide.
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

cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/attack.py
EOF
chmod +x /app/attack.sh

echo "HashCollisionGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
