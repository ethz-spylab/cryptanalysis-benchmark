#!/bin/bash

# Solution for T1_khichidi -> HashCollisionGame.
#
# Khichidi-1's block compression `digest()` carries only a SINGLE 32-bit word
# (H[0] = Z[7] of the previous block) between message blocks: the other seven
# chaining words H[1..7] are overwritten by the freshly-computed Z[0..6] before
# they are ever read. The mixing function mpp = lfsr o t_function o shuffling is
# a bijection on 32 bits, so we can construct, with complexity 1 and no search,
# two equal-length 64-byte messages that share their second block and arrive at
# it carrying the identical 32-bit word -> identical hash.
#
# Construction (offline-validated against the reference CLI):
#   - block1  = w0..w7  (random words)
#   - block1' = same words except w0 flipped and w7 recomputed via inverse-mpp
#               so that Z'[7] == Z[7]
#   - both messages append the same 32-byte block2.
#
# The HashCollisionGame simply hashes both submitted plaintexts (default
# 256-bit output) and accepts iff they are distinct and hash equal, so the
# attack just submits the precomputed pair. The values below are reproduced
# exactly by attack_references/T1_khichidi/poc_attack.py (make_collision()).

PT1="9e6b6cf8042db923a9eab70630cffdda786a6d2dbc051c6ceed8f1e7e9fb123d6465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f80818283"
PT2="8f495fbc042db923a9eab70630cffdda786a6d2dbc051c6ceed8f1e78f4a1a886465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f80818283"

cat <<PYEOF > /app/attack.py
import json
import subprocess
import sys

SERVER_URL = "http://game_controller:8000"

plaintext1 = "0x${PT1}"
plaintext2 = "0x${PT2}"

# (Optional) sanity-check via the hash oracle that the pair collides.
for label, pt in [("plaintext1", plaintext1), ("plaintext2", plaintext2)]:
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", f"{SERVER_URL}/oracle_query",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"oracle_type": "hash", "arguments": {"plaintext": pt}})],
        capture_output=True, text=True,
    )
    print(f"{label} hash oracle response: {result.stdout.strip()}")

# Submit the colliding pair.
print("\nSubmitting collision to HashCollisionGame...")
result = subprocess.run(
    ["curl", "-s", "-X", "POST", f"{SERVER_URL}/execute_current_stage",
     "-H", "Content-Type: application/json",
     "-d", json.dumps({"stage_payload": {"plaintext1": plaintext1, "plaintext2": plaintext2}})],
    capture_output=True, text=True,
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
