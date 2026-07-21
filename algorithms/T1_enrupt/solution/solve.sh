#!/bin/bash
#
# solve.sh for T1_enrupt's HashCollisionGame.
#
# EnRUPT-256 (the variant built by this task: w=64, P=2, s=4, H=8) is broken by
# the Indesteege-Preneel linearisation collision attack ("Practical Collisions
# for EnRUPT", attack_references/T1_enrupt/enrupt_paper.pdf). The paper gives an
# explicit colliding pair for EnRUPT-256 in its Table 10; both 48-byte messages
# hash to bd67517ca6c0412082e03b745ffc4a64e9f092c258c398b8449afecb7fc86f72.
#
# IMPORTANT: this only works because build_cli.sh now fixes the undefined
# behaviour in the reference `ir1` round macro (the `r++` is given its own
# sequence point). Before that fix, gcc -O3 miscompiled the round function so the
# built binary was NOT reference EnRUPT and this pair did not collide. With the
# fix, the binary matches all 256 byte-aligned official KAT vectors and the
# Table-10 pair collides exactly (verified offline against the local cli).

set -e

cat <<'PYEOF' > /app/attack.py
import subprocess
import json
import sys

SERVER_URL = "http://game_controller:8000"

# Indesteege-Preneel collision example for EnRUPT-256 (paper Table 10).
# Both messages are 48 bytes and hash to the same 256-bit digest.
plaintext1 = ("0x13c84b456270176e04f9317ec36ce7d3e121786a347411197f64a3c9"
              "40077576a14f9086fdc7334a413a769196062ca1")
plaintext2 = ("0x13c84b456a70176e04f9315c436ce7d3e1217848bc7411197f64a3cb"
              "48077576a14f9084fdc7334a413a769396062ca1")

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

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "HashCollisionGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
