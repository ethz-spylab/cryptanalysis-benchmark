#!/bin/bash
#
# READY-TO-USE solve.sh for T1_boole's HashCollisionGame — *but only correct once the CLI
# is rebuilt as the Boole32 variant* (see POC_NOTES.md, "blocker fix").
#
# As shipped, algorithms/T1_boole builds Boole64 (WORDSIZE=64), against which this colliding
# pair does NOT collide (the documented practical collision is 2^66 for Boole64, infeasible).
# This file is intentionally NOT placed in algorithms/T1_boole/solution/ because it would lose
# against the current Boole64 CLI. Once the build is switched to Boole32 (e.g. -DWORDSIZE=32),
# copy this to algorithms/T1_boole/solution/solve.sh — it wins instantly.
#
# Source of the colliding pair: BooleCollision.txt (Mendel/Nad/Schläffer, 2008-11-28).
# Both plaintexts hash to 3f71dd7bd86ac4731bc1567791d6fc8479c411530e3c8230d97cbca36c19e01f
# under Boole32-256 (verified locally with a -DWORDSIZE=32 build of this exact cli.c).

set -e

cat <<'PYEOF' > /app/attack.py
import subprocess
import json
import sys

SERVER_URL = "http://game_controller:8000"

# Published Boole32 colliding pair (NIST mailing list, 2008-11-28).
plaintext1 = ("0xa0bc0dbea1e5e09ebcb018243403415f0b177f217b31b82df5db2a23a866bb7c"
              "004ebc0fe11adc4555b36c86f59ed7bad7eb4405c3265558556eaf94980d9839"
              "596fd2d9d55ecff15df3155c10dc14fa22672d7587fbd016af0c15b84719bfdd")
plaintext2 = ("0xa0bc0dbea1e5e09ebcb01824cbfcbea00b177f217b31b82d0a24d5dca866bb7c"
              "004ebc0fe11adc4555b36c86f59ed7bad7eb4405c3265558556eaf94980d9839"
              "596fd2d9d55ecff15df3155cef23eb0522672d7587fbd01650f3ea474719bfdd")

for label, pt in [("plaintext1", plaintext1), ("plaintext2", plaintext2)]:
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", f"{SERVER_URL}/oracle_query",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"oracle_type": "hash", "arguments": {"plaintext": pt}})],
        capture_output=True, text=True
    )
    print(f"{label} hash: {result.stdout.strip()}")

result = subprocess.run(
    ["curl", "-s", "-X", "POST", f"{SERVER_URL}/execute_current_stage",
     "-H", "Content-Type: application/json",
     "-d", json.dumps({"stage_payload": {"plaintext1": plaintext1, "plaintext2": plaintext2}})],
    capture_output=True, text=True
)
print(f"Game response: {result.stdout.strip()}")
response = json.loads(result.stdout)
if response.get("stage_result", {}).get("Game won") == "Yes":
    print("SUCCESS: Hash collision accepted!")
else:
    print("FAILURE: collision not accepted (is the CLI built as Boole32?).")
    sys.exit(1)
PYEOF

cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/attack.py
EOF
chmod +x /app/attack.sh

echo "HashCollisionGame" > /app/security_game_choice.txt
