#!/bin/bash
# Reference solution for T1_hk17 targeting KEMSharedSecretRecoveryGame.
#
# HK17 is the octonion Diffie-Hellman KEM. Bernstein & Lange (pqc-forum,
# 2017-12-25) gave a ~p+1 linear-algebra break: from the public key
# (OA, OB, RB) and the encapsulation RA = x*OB*y (x,y in F_p[OA]), Eve writes
# RA = x*OB*y, brute-forces x in F_p + OA*F_p (only ~2p candidates),
# recovers (x, y), and computes the session octonion SK = x*RB*y -- the shared
# secret -- WITHOUT the private key. p = 65521, so this is ~2^16 trivial steps.
#
# This script needs NO oracle queries: the public key + encapsulation alone
# determine the shared secret. Pure Python, runs in well under a second.

cat <<'PYEOF' > /app/attack.py
import json
import subprocess

SERVER_URL = "http://game_controller:8000"
P = 65521


def curl_post(path, data):
    r = subprocess.run(
        ["curl", "-s", "-X", "POST", SERVER_URL + path,
         "-H", "Content-Type: application/json",
         "-d", json.dumps(data)],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise RuntimeError("curl failed: " + r.stderr)
    return json.loads(r.stdout)


# ---- octonion arithmetic (multiplication table from HK17 octonions.c) -------
def summ(o1, o2, m):
    return tuple((o1[i] + o2[i]) % m for i in range(8))


def scale(o, s, m):
    return tuple((s * o[i]) % m for i in range(8))


def multiply(o1, o2, m):
    a, b, c, d, e, f, g, h = o1
    i, j, k, l, mm, n, o, p = o2
    t1 = (a*i - b*j - c*k - d*l - e*mm - f*n - g*o - h*p) % m
    t2 = (a*j + b*i + c*mm + d*p - e*k + f*o - g*n - h*l) % m
    t3 = (a*k - b*mm + c*i + d*n + e*j - f*l + g*p - h*o) % m
    t4 = (a*l - b*p - c*n + d*i + e*o + f*k - g*mm + h*j) % m
    t5 = (a*mm + b*k - c*j - d*o + e*i + f*p + g*l - h*n) % m
    t6 = (a*n - b*o + c*l - d*k - e*p + f*i + g*j + h*mm) % m
    t7 = (a*o + b*n - c*p + d*mm - e*l - f*j + g*i + h*k) % m
    t8 = (a*p + b*l + c*o - d*j + e*n - f*mm - g*k + h*i) % m
    return (t1, t2, t3, t4, t5, t6, t7, t8)


def modprecip(x):
    x %= P
    if x == 0:
        raise ZeroDivisionError
    return pow(x, P - 2, P)


def octonionrecip(x):
    nrm = sum(xi * xi for xi in x) % P
    conj = (x[0], -x[1], -x[2], -x[3], -x[4], -x[5], -x[6], -x[7])
    return scale(conj, modprecip(nrm), P)


# ---- serialization: CLI hex <-> octonion tuples (8 LE int64 each) -----------
def strip0x(h):
    h = h.strip()
    return h[2:] if h[:2].lower() == "0x" else h


def b2o(b):
    return tuple(int.from_bytes(b[8*i:8*i+8], "little") % P for i in range(8))


def o2hex(o):
    return "0x" + b"".join(int(c % P).to_bytes(8, "little") for c in o).hex()


def parse_pk(pk_hex):
    b = bytes.fromhex(strip0x(pk_hex))
    assert len(b) == 720, len(b)
    return b2o(b[0:64]), b2o(b[64:128]), b2o(b[128:192])  # OA, OB, RB


def parse_ct(ct_hex):
    b = bytes.fromhex(strip0x(ct_hex))
    assert len(b) == 64, len(b)
    return b2o(b)  # RA


# ---- Bernstein-Lange recovery ----------------------------------------------
def recover_shared_secret(pk_hex, ct_hex):
    OA, OB, RB = parse_pk(pk_hex)
    RA = parse_ct(ct_hex)
    octonionrecip(RA)  # require RA invertible (holds w.h.p.)
    obrecip = octonionrecip(OB)
    for i in range(P):
        for j in (0, 1):
            if j == 0 and i != 1:
                continue
            x = summ((i, 0, 0, 0, 0, 0, 0, 0), scale(OA, j, P), P)
            try:
                xrecip = octonionrecip(x)
            except ZeroDivisionError:
                continue
            t = multiply(xrecip, RA, P)
            y = multiply(obrecip, t, P)
            if multiply(y, OA, P) == multiply(OA, y, P):
                SK = multiply(x, multiply(RB, y, P), P)
                return o2hex(SK)
    raise RuntimeError("Bernstein-Lange factorization failed (rare RA)")


# ---- Stage 0: receive public key + encapsulation ----------------------------
resp = curl_post("/execute_current_stage", {"stage_payload": {}})
print("Stage 0 response:", str(resp)[:200])
result = resp["stage_result"]
pk_hex = result["public_key"]
ct_hex = result["encapsulation"]

# ---- recover the shared secret (no private key, no oracle) ------------------
ss_hex = recover_shared_secret(pk_hex, ct_hex)
print("Recovered shared secret:", ss_hex[:48], "...")

# ---- Stage 1: submit recovered shared secret --------------------------------
resp = curl_post(
    "/execute_current_stage",
    {"stage_payload": {"recovered_shared_secret": ss_hex}},
)
print("Stage 1 response:", resp)
won = resp.get("stage_result", {}).get("Game won")
print("SUCCESS" if won == "Yes" else "FAILURE")
PYEOF

cat <<'EOF' > /app/attack.sh
#!/bin/bash
# Pure-Python (stdlib + curl only), no third-party deps required.
python3 /app/attack.py
EOF
chmod +x /app/attack.sh

echo "KEMSharedSecretRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
