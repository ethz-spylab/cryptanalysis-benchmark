#!/bin/bash
#
# CFPKM128 shared-secret recovery solution.
#
# Break (Steinfeld; Albrecht-Postlethwaite-Virdia, OFFICIAL COMMENT 2018):
# the CFPKM shared secret is ss = kem_rounding(b3) with b3[i] = b1[i]*b2[i] + e3[i],
# where b1 = public-key vector (unpack_pk(pk)) and b2 = ciphertext vector
# (unpack_ct(ct)). The error e3 has tiny entries (< RANGE=7) so it never flips the
# rounded MSBs. Hence ss[i] = kem_rounding(b1[i]*b2[i]) — recoverable from (pk, ct)
# alone, with NO secret key. We replicate the reference integer arithmetic exactly.

# Write the self-contained attack script (pure python3 stdlib — no deps).
cat <<'PY_EOF' > /app/cfpkm_attack.py
#!/usr/bin/env python3
import json, subprocess, sys

SERVER_URL = "http://game_controller:8000"

# CFPKM128 parameters (from KEMheader.h)
M = 81
SEEDSIZE = 48
Q = 1 << 50
B_BAR = 44          # LOG2_Q - B = 50 - 6
ROUND_ADD = 2 ^ 43  # reference C `2^(B_BAR-1)` is bitwise XOR (== 41), NOT a power
MASK64 = (1 << 64) - 1


def curl_post(url, data):
    r = subprocess.run(
        ["curl", "-s", "-X", "POST", url,
         "-H", "Content-Type: application/json",
         "-d", json.dumps(data)],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise RuntimeError(f"curl failed: {r.stderr}")
    return json.loads(r.stdout)


def strip0x(s):
    return s[2:] if s.lower().startswith("0x") else s


def unpack_pk(pk):
    """Mirror reference unpack_pk: b1[i] from 8 big-endian bytes after SEEDSIZE."""
    b1 = []
    for i in range(M):
        v = 0
        for j in range(7):
            v = (v + pk[i * 8 + j + SEEDSIZE]) & MASK64
            v = (v << 8) & MASK64
        v = (v + pk[i * 8 + 7 + SEEDSIZE]) & MASK64
        b1.append(v)
    return b1


def unpack_ct(ct):
    """Mirror reference unpack_ct: c = first M bytes; b2[i] from 8 bytes after M."""
    b2 = []
    for i in range(M):
        v = 0
        for j in range(7):
            v = (v + ct[i * 8 + j + M]) & MASK64
            v = (v << 8) & MASK64
        v = (v + ct[i * 8 + 7 + M]) & MASK64
        b2.append(v)
    return b2


def kem_rounding(w):
    out = bytearray(M)
    for i in range(M):
        rem = (w[i] + ROUND_ADD) & MASK64
        out[i] = ((rem % Q) >> B_BAR) & 0xFF
    return bytes(out)


def recover_shared_secret(pk_hex, ct_hex):
    pk = bytes.fromhex(strip0x(pk_hex))
    ct = bytes.fromhex(strip0x(ct_hex))
    b1 = unpack_pk(pk)
    b2 = unpack_ct(ct)
    w = [(b1[i] * b2[i]) & MASK64 for i in range(M)]
    return kem_rounding(w)


# Stage 0: receive public key and encapsulation.
resp = curl_post(f"{SERVER_URL}/execute_current_stage", {"stage_payload": {}})
sr = resp["stage_result"]
pk_hex = sr["public_key"]
ct_hex = sr["encapsulation"]
print(f"pk: {pk_hex[:48]}...", file=sys.stderr)
print(f"ct: {ct_hex[:48]}...", file=sys.stderr)

# Recover the shared secret from (pk, ct) — no secret key.
ss = recover_shared_secret(pk_hex, ct_hex)
ss_hex = "0x" + ss.hex()
print(f"recovered ss: {ss_hex}", file=sys.stderr)

# Stage 1: submit the recovered shared secret.
resp = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {"recovered_shared_secret": ss_hex}},
)
print(f"response: {resp}", file=sys.stderr)
if resp.get("stage_result", {}).get("Game won") == "Yes":
    print("SUCCESS: shared secret recovered.", file=sys.stderr)
    sys.exit(0)
print("FAILURE: shared secret recovery failed.", file=sys.stderr)
sys.exit(1)
PY_EOF

# Write the attack launcher (self-contained; only python3 stdlib + curl).
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/cfpkm_attack.py
EOF
chmod +x /app/attack.sh

# Declare the chosen security game.
echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
