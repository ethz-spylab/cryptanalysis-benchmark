#!/bin/bash
# Reference solution for T1_lotus (LOTUS-128 KEM) targeting KEMPrivateKeyRecoveryGame.
#
# Attack: Lepoint's failure-leak key recovery (OFFICIAL COMMENT: LOTUS, Dec 2017).
# LOTUS decapsulation computes  ss = csym XOR H(sigma)  and returns it BEFORE the
# re-encryption ciphertext check; on a forced verification failure the shared
# secret is leaked anyway. Setting csym = 0 makes  ss = SHA-512(sigma||0x01)[:16],
# so a crafted ciphertext  c1 = 2^k * e_i ,  c2 +/- q/8  probes the secret matrix.
# We recover S exactly, re-pack it (pack_sk) and append the known packed public
# key to reconstruct the byte-exact private key, then submit it.
#
# PERFORMANCE: a single decapsulate leaks ss = SHA512(sigma||0x01)[:16] over the
# FULL 128-coordinate decrypted message. The naive recovery (lotus_recover.recover_S)
# uses it as a 1-bit zero-test and needs ~480k queries (~12h over the oracle). This
# solution uses lotus_fast.recover_S_threshold: with c1 = e_i the message is
# t = c2 + S[i][:], so setting c2[j] = q/4 - g makes sigma_j = 1 iff S[i][j] >= g
# (a per-coordinate threshold test). The small secret coefficients (observed |S|<=5)
# are binary-searched directly over [-7,7] (4 rounds, no bit-levels / no baseline),
# reading G=20 coordinates per query by matching ss against precomputed hash tables
# (rest pinned to sigma=0 via c2=0). This cuts the query count ~30x to ~16k (~24-29min
# over the oracle). Verified locally to recover the byte-exact private key (sk match);
# a rare |S|>7 coordinate is resolved exactly by an extended per-coordinate search.
#
# This attack depends on the decapsulate oracle exposing the failure-time shared
# secret; the in-repo cli.c gating was removed for T1_lotus (decapsulate prints
# shared_secret_key regardless of the return code). The pure-Python helpers
# (lotus_pack.py, lotus_recover.py, lotus_fast.py) ship in this solution/ folder so
# the attack is fully self-contained in the verifier's isolated environment.

set -e

# Bundle the pure-Python pack/recover helpers into the self-contained attack.
# The helpers live alongside this script in the solution/ folder, which IS copied
# into the task environment (unlike attack_references/, which is not shipped).
SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /app/lotus_attack

# Ship the helper modules next to the attack script so the verifier's isolated
# environment has them (they are pure-Python, no third-party deps). set -e makes
# this fail loudly if a helper is ever missing, rather than silently skipping.
cp "$SOLUTION_DIR/lotus_pack.py" "$SOLUTION_DIR/lotus_recover.py" \
   "$SOLUTION_DIR/lotus_fast.py" /app/lotus_attack/

cat > /app/lotus_attack/run_attack.py <<'PYEOF'
import json
import subprocess
import sys
import time

sys.path.insert(0, "/app/lotus_attack")
import lotus_recover as R  # noqa: E402
import lotus_fast as LF  # noqa: E402

SERVER = "http://game_controller:8000"


def post(path, payload):
    # Robust against transient HTTP hiccups: a single empty/failed curl response
    # over ~16k queries would otherwise crash json.loads. Retry a few times.
    body = json.dumps(payload)
    last = ""
    for _ in range(6):
        # Send the body on stdin (--data-binary @-), NOT as a curl -d argv: the
        # final submission carries the 714 KB private key (~1.4 MB of hex) which
        # would exceed ARG_MAX as a command-line argument.
        r = subprocess.run(
            ["curl", "-s", "--max-time", "90", "-X", "POST", f"{SERVER}{path}",
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
    raise RuntimeError(f"POST {path} failed after retries (last stdout={last[:200]!r})")


# Stage 0: fetch the public key.
resp = post("/execute_current_stage", {"stage_payload": {}})
pk_hex = resp["stage_result"]["public key"]
if pk_hex.startswith(("0x", "0X")):
    pk_hex = pk_hex[2:]
pk_bytes = bytes.fromhex(pk_hex)
print(f"[*] public key: {len(pk_bytes)} bytes", flush=True)


def oracle(ct_hex):
    """Query the decapsulate oracle (private key auto-injected by the game)."""
    resp = post("/oracle_query", {
        "oracle_type": "decapsulate",
        "arguments": {"encapsulation": ct_hex},
    })
    res = resp.get("oracle_result", {})
    ss = res.get("shared_secret_key")
    if ss is None:
        raise RuntimeError(
            "decapsulate oracle did not return a shared secret "
            f"(got {res}); the failure-leak channel is closed by cli.c "
            "(it prints FAILED instead of the leaked shared secret)."
        )
    if ss.startswith(("0x", "0X")):
        ss = ss[2:]
    return bytes.fromhex(ss)


_t0 = time.time()


def progress(i):
    print(f"[*] recovering S, row {i}/576  (t={time.time()-_t0:.0f}s)", flush=True)


print("[*] building candidate-hash tables (G=20)...", flush=True)
tables = LF.build_group_tables(20)
print("[*] recovering secret matrix S (value-based threshold search)...", flush=True)
S, n_extended = LF.recover_S_threshold(oracle, tables, B=7, progress=progress)
if n_extended:
    print(f"[*] {n_extended} coordinate(s) needed the extended search (|S|>7)",
          flush=True)

sk_bytes = R.serialize_sk(S, pk_bytes)
recovered = "0x" + sk_bytes.hex()
print(f"[*] reconstructed private key: {len(sk_bytes)} bytes "
      f"(t={time.time()-_t0:.0f}s)", flush=True)

resp = post("/execute_current_stage",
            {"stage_payload": {"recovered_private_key": recovered}})
print(f"[*] submit result: {resp}", flush=True)
won = resp.get("stage_result", {}).get("Game won") == "Yes"
print("SUCCESS" if won else "FAILURE", flush=True)
sys.exit(0 if won else 1)
PYEOF

cat > /app/attack.sh <<'EOF'
#!/bin/bash
# Self-contained: pure-Python attack (no third-party deps).
python3 /app/lotus_attack/run_attack.py
EOF
chmod +x /app/attack.sh

echo "KEMPrivateKeyRecoveryGame" > /app/security_game_choice.txt

echo "solve.sh finished: wrote /app/attack.sh and /app/security_game_choice.txt"
