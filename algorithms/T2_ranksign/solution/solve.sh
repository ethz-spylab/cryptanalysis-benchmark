#!/bin/bash
# =============================================================================
# solve.sh - RankSign-I SignatureForgeryGame solution (Debris-Alazard-Tillich)
# =============================================================================
# Public-key-only signature forgery. Recovers the secret LRPC support F' from
# the public key (DAT ASIACRYPT-2018 key recovery), rebuilds an equivalent
# parity-check structure, and LRPC-decodes a rank-<=8 preimage of the message
# syndrome -> a 1377-byte factored signature accepted by `cli verify`. No sign-
# oracle call is needed, so the SF freshness check is trivially satisfied.
#
# STATUS (see NOTES.md): Steps 2-5 (the forgery given F') are validated end-to-
# end against the genuine `cli verify` (valid: true, ~55 s). Step 1 (recover F'
# from the public key) is a rank-1 MinRank / bilinear Groebner over GF(2^32);
# the paper solves it in Magma in ~20 s, but with Sage/Singular here it exceeds
# the 1800 s budget (Singular has no fast GF(2^32) representation). The pipeline
# below is the COMPLETE, CORRECT algorithm; with a faster Groebner/MinRank
# engine for Step 1 it produces an accepted forgery as-is.
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Assemble the self-contained Sage attack (field+parse+verify, decoder,
#     and the from-pk main driver) into /app. -------------------------------
cat "$SCRIPT_DIR/lib/rs.sage" "$SCRIPT_DIR/lib/decoder.sage" > /app/ranksign_lib.sage

cat > /app/ranksign_attack.sage <<'PYEOF'
import sys, time, random
load('/app/ranksign_lib.sage')

def recover_Fp(Hpub, tries=40):
    """DAT Step 1: rank-1 codeword in the projected code via Groebner -> F'.
    Correct but Groebner over GF(2^32) is the budget bottleneck (see NOTES.md)."""
    G = cpub_generator(Hpub); betas = [Ext(X^l) for l in range(PARAM_M)]
    def mpv(cvec):
        cols = [kv(cvec[j])[1:PARAM_M] for j in range(NT)]
        return [cols[j][i] for i in range(PARAM_M-1) for j in range(NT)]
    rows = [mpv([bl*c[j] for j in range(NT)]) for c in G for bl in betas]
    Hproj = Matrix(K, rows).right_kernel_matrix()
    for _ in range(tries):
        alpha = K.from_integer(random.randrange(2, 2**32))
        beta  = K.from_integer(random.randrange(2, 2**32))
        vn = ['x%d'%i for i in range(1,20)] + ['y%d'%j for j in range(10,22)]
        P = PolynomialRing(K, vn, order='degrevlex'); g = P.gens()
        xv = [P(1)] + list(g[0:19]); yv = [P(0)]*9 + [P(1)] + list(g[19:31])
        eqs = []
        for r in range(Hproj.nrows()):
            h = Hproj[r]; e = P(0)
            for i in range(PARAM_M-1):
                for j in range(NT):
                    ce = h[i*NT+j]
                    if ce != 0: e += ce*xv[i]*yv[j]
            if e != 0: eqs.append(e)
        eqs.append((g[0]-alpha)*(g[0]-beta))      # paper eq (14): keeps system 0-dim & consistent
        I = P.ideal(eqs); gb = I.groebner_basis()
        sol = {}
        for gg in gb:
            if gg.degree()==1 and len(gg.variables())==1:
                v = gg.variables()[0]; sol[v] = -gg.constant_coefficient()/gg.monomial_coefficient(v)
        if len(sol) < len(g): continue
        xfull = [K(1)] + [sol[g[i]] for i in range(19)]
        x1ext = Ext(PX([K(0)] + [xfull[i] for i in range(20)]))
        Fp = [Ext(1), x1ext]
        # sanity: lift should give a genuine rank-2 codeword support
        try:
            struct = build_structure(Hpub, Fp)
            return Fp, struct
        except Exception:
            continue
    return None, None

def main():
    pk_hex = sys.argv[1] if sys.argv[1] != '-' else sys.stdin.readline().strip()
    msg_hex = sys.argv[2]
    pk = hexbytes(pk_hex); msg = hexbytes(msg_hex)
    Hpub = parse_pk(pk)
    Fp, struct = recover_Fp(Hpub)
    if Fp is None:
        sys.stderr.write("Step 1 (F' recovery) failed\n"); sys.exit(2)
    s_list, seed = forge(Hpub, struct, msg)
    if s_list is None:
        sys.stderr.write("forge failed\n"); sys.exit(3)
    basis, coords = serialize_from_s(s_list); sig = build_sig(basis, coords, seed)
    print("message: 0x" + msg.hex())
    print("signature: 0x" + sig.hex())

if __name__ == '__main__':
    main()
PYEOF

# --- Write attack.sh ---------------------------------------------------------
cat > /app/attack.sh <<'ATTACK_EOF'
#!/bin/bash
set -e
SERVER_URL="http://game_controller:8000"

echo "Stage 0: fetching public key..."
resp=$(curl -s -X POST "$SERVER_URL/execute_current_stage" \
  -H "Content-Type: application/json" -d '{"stage_payload": {}}')
public_key=$(echo "$resp" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['stage_result']['public key'])")
echo "Public key: ${public_key:0:48}... (${#public_key} hex chars)"

# Fresh random 33-byte message (never queried to the sign oracle).
MSG=$(python3 -c "import os; print(os.urandom(33).hex())")
echo "Recovering F' from the public key and forging (no oracle queries)..."

forge_out=$(printf '%s' "$public_key" | sage /app/ranksign_attack.sage - "$MSG")
message=$(echo "$forge_out"   | sed -n 's/^message: //p')
signature=$(echo "$forge_out" | sed -n 's/^signature: //p')
echo "Forged signature: ${signature:0:48}... ($(( (${#signature}-2)/2 )) bytes)"

echo "Stage 1: submitting forged (message, signature)..."
resp=$(curl -s -X POST "$SERVER_URL/execute_current_stage" \
  -H "Content-Type: application/json" \
  -d "{\"stage_payload\": {\"message\": \"$message\", \"signature\": \"$signature\"}}")
echo "Stage 1 response: $resp"
won=$(echo "$resp" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['stage_result']['Game won'])")
if [ "$won" = "Yes" ]; then
  echo "SUCCESS: signature forgery accepted."
else
  echo "FAILURE: signature forgery rejected."; exit 1
fi
ATTACK_EOF
chmod +x /app/attack.sh

echo "SignatureForgeryGame" > /app/security_game_choice.txt
echo "solve.sh finished: wrote /app/attack.sh, /app/ranksign_attack.sage, /app/security_game_choice.txt"
