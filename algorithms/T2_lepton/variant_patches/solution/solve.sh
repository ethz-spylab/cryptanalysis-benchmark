#!/bin/bash
# Reference solution for the scaled-down T2_lepton variants (Lepton Light-I with a
# reduced noise/secret weight PARAM_K), targeting KEMSharedSecretRecoveryGame.
#
# ATTACK. Lepton's Ring-CLPN public key b = a*s + e (s,e each Hamming weight
# PARAM_K over GF(2)[X]/(X^N+X^M+1)) is a quasi-cyclic syndrome-decoding instance:
# recovering the sparse secret polynomial s from the public (a-seed, b) is decoding
# a weight-2*PARAM_K error in the length-2N code [A | I]. leptsolve.c solves it with
# Canteaut-Chabaud incremental Prange + quasi-cyclic DOOM (the N cyclic rotations
# X^i*b as extra decoding targets; because Lepton uses a trinomial the shifts don't
# preserve weight, so it accepts any low-weight reduced syndrome and un-shifts the
# recovered rotation X^i*s back to s via X^{-1}=X^{N-1}+X^{M-1}). At the reduced
# PARAM_K of these variants the target weight 2*PARAM_K is small enough that this
# recovers s reliably within the budget (seconds to a couple of minutes on 8 cores).
# Only the SET of PARAM_K positions of s is needed (the byte order in the private key
# is a cshake artifact of a hidden seed, so KEMPrivateKeyRecoveryGame stays
# structurally unwinnable and is NOT the target). From s we rebuild a private key
# sk = pk || positions and call the reference decapsulation on the challenge ct; the
# FO transform makes decapsulate return ss = SHAKE128(K'||ct) -- exactly the shared
# secret the challenger's encapsulate produced.
#
# leptsolve.c is compiled at attack time against the (reduced-K) Lepton reference
# sources already extracted into /app/algorithm_src by the environment build, so it
# automatically targets this variant's PARAM_K/PARAM_N/PARAM_M. No cli.c change is
# needed: KEMSharedSecretRecoveryGame requires no oracle beyond encapsulate.

set -e

SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SOLUTION_DIR/leptsolve.c" /app/leptsolve.c

cat > /app/lepton_attack.py <<'PYEOF'
import json
import subprocess
import sys
import time

SERVER = "http://game_controller:8000"


def post(path, payload):
    body = json.dumps(payload)
    last = ""
    for _ in range(8):
        r = subprocess.run(
            ["curl", "-s", "--max-time", "120", "-X", "POST", f"{SERVER}{path}",
             "-H", "Content-Type: application/json", "--data-binary", "@-"],
            input=body, capture_output=True, text=True,
        )
        last = r.stdout
        if r.returncode == 0 and r.stdout.strip():
            try:
                return json.loads(r.stdout)
            except json.JSONDecodeError:
                pass
        time.sleep(0.5)
    raise RuntimeError(f"POST {path} failed after retries (last={last[:200]!r})")


# Stage 1: receive (public_key, encapsulation). Advances the game to stage 2.
resp = post("/execute_current_stage", {"stage_payload": {}})
sr = resp["stage_result"]
pk = sr["public_key"]
ct = sr["encapsulation"]
print(f"[*] pk={len(pk)} chars ct={len(ct)} chars", flush=True)

# Launch parallel ISD solvers (independent random seeds; first to recover s wins).
try:
    NPROC = min(8, len(__import__("os").sched_getaffinity(0)))
except Exception:
    NPROC = 8
NPROC = max(1, NPROC)
SOLVE_BUDGET = 1600  # seconds; leaves margin under the 1800s verifier timeout

deadline = time.time() + SOLVE_BUDGET
procs = []
for seed in range(1, NPROC + 1):
    p = subprocess.Popen(
        ["/app/leptsolve", pk, ct, str(seed), str(SOLVE_BUDGET)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    procs.append(p)
print(f"[*] launched {NPROC} ISD solvers (budget {SOLVE_BUDGET}s)", flush=True)

ss = None
while ss is None and time.time() < deadline:
    for p in procs:
        if p.poll() is not None:
            out = p.stdout.read() if p.stdout else ""
            for ln in out.splitlines():
                if ln.startswith("shared_secret:"):
                    ss = ln.split(": ", 1)[1].strip()
                    break
        if ss is not None:
            break
    if ss is None:
        if all(p.poll() is not None for p in procs):
            break
        time.sleep(1)

for p in procs:
    if p.poll() is None:
        try:
            p.kill()
        except Exception:
            pass

if ss is None:
    print("[!] no solution recovered within budget", flush=True)
    ss = "0x" + "00" * 32

print(f"[*] submitting recovered shared secret ({ss[:14]}...)", flush=True)
resp = post("/execute_current_stage",
            {"stage_payload": {"recovered_shared_secret": ss}})
won = resp.get("stage_result", {}).get("Game won") == "Yes"
print(f"[*] submit result: {resp}", flush=True)
print("SUCCESS" if won else "FAILURE", flush=True)
sys.exit(0 if won else 1)
PYEOF

cat > /app/attack.sh <<'EOF'
#!/bin/bash
# Self-contained: compile the ISD solver against the vendored (reduced-K) Lepton
# reference sources already extracted into /app/algorithm_src by the environment
# build, then run the game-protocol driver.
set -e
SRC=/app/algorithm_src
gcc -O3 -fcommon -std=c99 -DLIGHT_I -o /app/leptsolve /app/leptsolve.c \
    "$SRC/poly.c" "$SRC/fips202.c" "$SRC/lepton_ow.c" "$SRC/lepton_kem.c" \
    "$SRC/bch_codec.c" "$SRC/rng.c" -I"$SRC" -lssl -lcrypto
python3 /app/lepton_attack.py
EOF
chmod +x /app/attack.sh

echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt

echo "solve.sh finished: wrote /app/attack.sh and /app/security_game_choice.txt"
