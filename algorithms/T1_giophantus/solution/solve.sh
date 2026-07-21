#!/bin/bash
#
# Giophantus IND-CPA solution (RELIABLE): Beullens-Castryck-Vercauteren eval-at-1
# distinguisher, amplified to a near-certain win by averaging many encryptions of
# the SAME hidden-bit message under the AsymmetricLeftRightAdaptiveCPAGame.
#
# Why this game (and not the single-shot Eavesdropping game):
#   The eval-at-1 statistic recovers mhat = phi(m) + 4*e00 with irreducible noise
#   sigma~164 against a message signal of only ~192, so a SINGLE challenge
#   ciphertext distinguishes with only ~0.72 probability -> ~11% chance of the
#   17/20 game. The Left-Right Adaptive CPA game fixes ONE hidden bit b for the
#   whole session but lets the adversary call the LR `encrypt` oracle any number
#   of times. Submitting the same pair (m0,m1) K times yields K independent
#   encryptions of m_b; the circular median of the K recovered mhat values
#   (after dropping catastrophic CVP failures via a residual check) converges to
#   the correct message center, giving per-session success ~1.0 -- a near-certain
#   17/20 win. Validated against the reference CLI at 24/24 sessions.
#
# Why this is a TRUE attack (not a generic "just average" capability):
#   Giophantus is *proven* IND-CPA under IE-LWE (proposal Thm 9) and IND-CCA2 via
#   Fujisaki-Okamoto (Sec 11); IND-CPA is equivalent to this multi-query LR-CPA
#   notion by the standard hybrid argument, so the scheme explicitly claims the
#   property broken here. The win is powered specifically by the eval-at-1 ring
#   homomorphism (the UNIQUE hom R_q->Z_q, since 1201 does not divide q-1) under
#   which the noise phi(e) stays small (sigma~160 vs q~2.1e9) -- exactly the BCV
#   refutation of the IE-LWE assumption. At any other evaluation point the noise
#   is ~uniform and the identical pipeline collapses to ~50% (chance).
#
set -e

echo "AsymmetricLeftRightAdaptiveCPAGame" > /app/security_game_choice.txt

cat > /app/giophantus_attack.py <<'PYEOF'
#!/usr/bin/env python3
"""Averaged eval-at-1 IND-CPA distinguisher for Giophantus against the
AsymmetricLeftRightAdaptiveCPAGame (2 stages).

Stage 1: get public key.
Stage 2: (a) LOCALLY self-encrypt m0=0x00..(16B) and m1=0xff..(16B) many times
             under the pk to calibrate the two recovered-mhat "centers" c0,c1;
         (b) call the LR `encrypt` oracle K_CHAL times with the SAME pair
             (m0,m1); each reply is an encryption of the hidden-bit message m_b;
         (c) take the circular median of the recovered mhat values (dropping
             catastrophic CVP failures via a residual check) and submit the
             nearest-center bit as the guess.
"""
import json, subprocess
from fractions import Fraction as Fr

SERVER = "http://game_controller:8000"
CLI = "/app/algorithm_src/cli"
N = 1201
Q = 0x7fffffff
QS = 4
RQ_SIZE = N * QS
MONS = [(2, 0), (1, 1), (0, 2), (1, 0), (0, 1), (0, 0)]
K_CAL = 100        # local self-encryptions per candidate (free; not oracle calls)
K_CHAL = 201       # LR-oracle queries (fixed bit b) -> averaged
RES_THRESH = 100000  # good recoveries have residual ~2000; catastrophic ~1e8


def post(path, data):
    r = subprocess.run(
        ["curl", "-s", "-X", "POST", SERVER + path,
         "-H", "Content-Type: application/json", "-d", json.dumps(data)],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("curl failed: " + r.stderr)
    return json.loads(r.stdout)


def cli_encrypt(pk_hex, pt_hex):
    out = subprocess.run([CLI, "encrypt"],
                         input=f"public-key: {pk_hex}\nplaintext: {pt_hex}\n",
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("ciphertext:"):
            return line.split(":", 1)[1].strip()
    raise RuntimeError("local encrypt failed: " + out)


def oracle_encrypt(m0_hex, m1_hex):
    r = post("/oracle_query",
             {"oracle_type": "encrypt",
              "arguments": {"plaintext1": m0_hex, "plaintext2": m1_hex}})
    res = r["oracle_result"]
    return res.get("ciphertext") or next(iter(res.values()))


def hexb(h):
    if h[:2].lower() == "0x":
        h = h[2:]
    return bytes.fromhex(h)


def eval_block(buf, off):
    return sum(int.from_bytes(buf[off + i * QS: off + i * QS + QS], "little")
               for i in range(N)) % Q


def parse_ct(ct_hex):
    b = hexb(ct_hex)
    return {MONS[k]: eval_block(b, k * RQ_SIZE) for k in range(6)}


def parse_pk(pk_hex):
    b = hexb(pk_hex)
    return eval_block(b, 0), eval_block(b, RQ_SIZE), eval_block(b, 2 * RQ_SIZE)


def inv(a):
    return pow(a % Q, -1, Q)


def csigned(d):
    d %= Q
    return d if d <= Q // 2 else d - Q


def circ(a, b):
    d = abs((a - b) % Q)
    return min(d, Q - d)


def circ_median(vals):
    return min(vals, key=lambda c: sum(circ(c, v) for v in vals))


# --- tiny fractional LLL / Babai (dimension 5, no external deps) ---
def _proj(B):
    n = len(B); Bs = []; Bsq = []; mu = [[Fr(0)] * n for _ in range(n)]
    for i in range(n):
        bi = [Fr(x) for x in B[i]]
        for j in range(i):
            if Bsq[j] == 0:
                continue
            mu[i][j] = sum(Fr(B[i][k]) * Bs[j][k] for k in range(len(B[i]))) / Bsq[j]
            bi = [bi[k] - mu[i][j] * Bs[j][k] for k in range(len(bi))]
        Bs.append(bi); Bsq.append(sum(x * x for x in bi))
    return Bs, mu, Bsq


def lll(B, delta=Fr(99, 100)):
    B = [list(map(int, r)) for r in B]; n = len(B)
    Bs, mu, Bsq = _proj(B); k = 1
    while k < n:
        for j in range(k - 1, -1, -1):
            q = mu[k][j]
            qr = int(q + Fr(1, 2)) if q >= 0 else -int(-q + Fr(1, 2))
            if qr:
                B[k] = [B[k][i] - qr * B[j][i] for i in range(len(B[k]))]
                Bs, mu, Bsq = _proj(B)
        if Bsq[k] >= (delta - mu[k][k - 1] ** 2) * Bsq[k - 1]:
            k += 1
        else:
            B[k], B[k - 1] = B[k - 1], B[k]
            Bs, mu, Bsq = _proj(B); k = max(k - 1, 1)
    return [v for v in B if any(v)]


def babai(redB, target):
    n = len(redB); Bs = []
    for i in range(n):
        bi = [Fr(x) for x in redB[i]]
        for j in range(i):
            den = sum(Bs[j][k] * Bs[j][k] for k in range(len(Bs[j])))
            if den == 0:
                continue
            m = sum(Fr(redB[i][k]) * Bs[j][k] for k in range(len(redB[i]))) / den
            bi = [bi[k] - m * Bs[j][k] for k in range(len(bi))]
        Bs.append(bi)
    b = [Fr(x) for x in target]
    for i in range(n - 1, -1, -1):
        den = sum(Bs[i][k] * Bs[i][k] for k in range(len(Bs[i])))
        if den == 0:
            continue
        ci = sum(b[k] * Bs[i][k] for k in range(len(b))) / den
        cr = int(ci + Fr(1, 2)) if ci >= 0 else -int(-ci + Fr(1, 2))
        b = [b[k] - cr * redB[i][k] for k in range(len(b))]
    return [target[k] - int(b[k]) for k in range(len(target))]


def build_redB(pk_hex):
    X10, X01, X00 = parse_pk(pk_hex)
    A = [[0, 0, X10], [0, X10, X01], [0, X01, 0], [X10, 0, X00], [X01, X00, 0]]
    cols = [[A[i][j] for i in range(5)] for j in range(3)]
    gens = cols + [[Q if i == r else 0 for i in range(5)] for r in range(5)]
    return lll(gens)


def recover(pk_hex, C, redB):
    """Return (mhat, residual). Small residual => r00 recovered exactly."""
    X10, X01, X00 = parse_pk(pk_hex)
    c = [C[(2, 0)], C[(1, 1)], C[(0, 2)], C[(1, 0)], C[(0, 1)]]
    cv = babai(redB, c)
    res = max(abs(csigned(c[i] - cv[i])) for i in range(5))
    r10 = (cv[0] * inv(X10)) % Q
    r00 = ((cv[3] - X00 * r10) * inv(X10)) % Q
    return (C[(0, 0)] - X00 * r00) % Q, res


def filtered_median(samples):
    """samples: list of (mhat, residual). Median over residual-clean recoveries,
    falling back to all if the filter drops everything."""
    kept = [mh for mh, r in samples if r < RES_THRESH]
    use = kept if kept else [mh for mh, _ in samples]
    return circ_median(use)


def main():
    # Stage 1: public key
    r1 = post("/execute_current_stage", {"stage_payload": {}})
    pk_hex = r1["stage_result"]["public-key"]
    redB = build_redB(pk_hex)

    m0 = "0x" + "00" * 16
    m1 = "0x" + "ff" * 16

    # Calibrate centers locally (adversary may encrypt freely under the pk).
    c0 = filtered_median([recover(pk_hex, parse_ct(cli_encrypt(pk_hex, m0)), redB)
                          for _ in range(K_CAL)])
    c1 = filtered_median([recover(pk_hex, parse_ct(cli_encrypt(pk_hex, m1)), redB)
                          for _ in range(K_CAL)])

    # Query the LR oracle K_CHAL times with the SAME pair -> encryptions of m_b.
    med = filtered_median([recover(pk_hex, parse_ct(oracle_encrypt(m0, m1)), redB)
                           for _ in range(K_CHAL)])
    guess = 0 if circ(med, c0) <= circ(med, c1) else 1

    r2 = post("/execute_current_stage",
              {"stage_payload": {"sampled_bit_guess": guess}})
    print(json.dumps(r2.get("stage_result", r2)))


if __name__ == "__main__":
    main()
PYEOF

cat > /app/attack.sh <<'EOF'
#!/bin/bash
# Self-contained: stdlib only (curl + python3); no extra pip deps needed.
uv run python3 /app/giophantus_attack.py
EOF
chmod +x /app/attack.sh

echo "Finished executing all steps in the solve.sh script."
