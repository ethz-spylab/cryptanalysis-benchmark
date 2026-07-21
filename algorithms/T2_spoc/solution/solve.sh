#!/bin/bash
#
# Reference solution for T1_spoc (SpoC-128 / sLiSCP-light-256, NIST LWC round 2).
#
# Game: SymmetricTargetKeyRecoveryGame (full secret-key recovery).
#
# The break (2 chosen-plaintext queries, deterministic, probability 1):
#
#   SpoC-128 initialises its 256-bit state by *loading* the 128-bit nonce into
#   the rate half (subblocks S0,S2) and the 128-bit key into the masked-capacity
#   half (subblocks S1,S3) — with NO permutation applied during init (unlike
#   SpoC-64). Tag generation XORs the domain-separation byte 0x80 into state[0],
#   which in the freshly loaded state is an adversary-controlled *nonce* byte.
#   The permutation Pi = sLiSCP-light-256 is public and invertible.
#
#   Let X = load(N1, K).
#   Query A: nonce=N1, empty AD, plaintext = one 16-byte zero block.
#            One block does Pi(X) then C = Z' XOR M; with M=0 the first 16
#            ciphertext bytes are the RATE half (S0,S2) of Pi(X).
#   Query B: nonce=N2 = N1 with byte0 XOR 0x80, empty AD, empty plaintext.
#            init loads state whose byte0 = N1[0]^0x80; gentag does state[0]^=0x80,
#            restoring byte0 to N1[0] => the permutation input is exactly X.
#            The 16-byte tag is then the CAPACITY half (S1,S3) of Pi(X).
#
#   Concatenate to get the full Pi(X), invert the public permutation to recover
#   X = load(N1,K), and read K straight out of the capacity subblocks. Done.

cat <<'PYEOF' > /app/spoc_attack.py
import json
import re
import subprocess
import sys

CLIENT = "/app/game_controller_client.py"

# ── sLiSCP-light-256 permutation (pure stdlib), matching the SpoC reference ──
SC1 = [0x8, 0x86, 0xe2, 0x89, 0xe6, 0xca, 0x17, 0x8e, 0x64,
       0x6b, 0x6f, 0x2c, 0xdd, 0x99, 0xea, 0x0f, 0x04, 0x43]
SC2 = [0x64, 0x6b, 0x6f, 0x2c, 0xdd, 0x99, 0xea, 0xf, 0x4,
       0x43, 0xf1, 0x44, 0x73, 0xe5, 0x0b, 0x47, 0xb2, 0xb5]
RC1 = [0xf, 0x4, 0x43, 0xf1, 0x44, 0x73, 0xe5, 0xb, 0x47,
       0xb2, 0xb5, 0x37, 0x96, 0xee, 0x4c, 0xf5, 0x7, 0x82]
RC2 = [0x47, 0xb2, 0xb5, 0x37, 0x96, 0xee, 0x4c, 0xf5, 0x7,
       0x82, 0xa1, 0x78, 0xa2, 0xb9, 0xf2, 0x85, 0x23, 0xd9]
NSTEPS = 18
MASK = 0xffffffff

# rate  = subblocks S0,S2 ; masked capacity = subblocks S1,S3 (byte positions)
RATE = [0, 1, 2, 3, 4, 5, 6, 7, 16, 17, 18, 19, 20, 21, 22, 23]
CAP = [8, 9, 10, 11, 12, 13, 14, 15, 24, 25, 26, 27, 28, 29, 30, 31]


def rotl32(w, s):
    return ((w << s) | (w >> (32 - s))) & MASK


def f32(x):  # Simeck round function: (x <<< 1) ^ (x & (x <<< 5))
    return (rotl32(x, 1) ^ (x & rotl32(x, 5))) & MASK


def _w(b, o):
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


def _pw(w):
    return bytes([(w >> 24) & 0xff, (w >> 16) & 0xff, (w >> 8) & 0xff, w & 0xff])


def simeck_box_inv(out8, rc):
    # forward Simeck box is an 8-round Feistel: (L,R) -> (f(L)^R^c, L)
    L = _w(out8, 0)
    R = _w(out8, 4)
    for i in range(7, -1, -1):
        c = 0xfffffffe ^ ((rc >> i) & 1)
        pL = R
        pR = (L ^ f32(R) ^ c) & MASK
        L, R = pL, pR
    return _pw(L) + _pw(R)


def _xor(a, b):
    return bytes(p ^ q for p, q in zip(a, b))


def _const(sc):
    return bytes([0xff] * 7 + [sc])


def permute_inv(state):
    x = [bytearray(state[0:8]), bytearray(state[8:16]),
         bytearray(state[16:24]), bytearray(state[24:32])]
    for i in range(NSTEPS - 1, -1, -1):
        y0, y1, y2, y3 = bytes(x[0]), bytes(x[1]), bytes(x[2]), bytes(x[3])
        # forward: x0'=F(x1); x2'=F(x3); x3'=x0^F(x1)^c1; x1'=x2^F(x3)^c2
        x1 = simeck_box_inv(y0, RC1[i])
        x3 = simeck_box_inv(y2, RC2[i])
        x0 = _xor(_xor(y3, y0), _const(SC1[i]))
        x2 = _xor(_xor(y1, y2), _const(SC2[i]))
        x = [bytearray(x0), bytearray(x1), bytearray(x2), bytearray(x3)]
    return bytes(x[0]) + bytes(x[1]) + bytes(x[2]) + bytes(x[3])


# ── Game-controller helpers ─────────────────────────────────────────────
def call(action, payload=None):
    cmd = ["uv", "run", CLIENT, "--action", action]
    if payload is not None:
        cmd += ["--json", json.dumps(payload)]
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def encrypt(nonce_hex, pt_hex):
    """Query the encrypt oracle; return the ciphertext(+tag) bytes."""
    out = call(
        "oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {"plaintext": pt_hex, "nonce": nonce_hex},
        },
    )
    m = re.search(r"['\"]ciphertext['\"]\s*:\s*['\"](0x[0-9a-fA-F]+)['\"]", out)
    if not m:
        sys.stderr.write("ENCRYPT parse failure: " + out[:300] + "\n")
        raise SystemExit(1)
    return bytes.fromhex(m.group(1)[2:])


# ── The attack ──────────────────────────────────────────────────────────
N1 = bytes(16)                       # any nonce; fixed for reproducibility
N2 = bytes([N1[0] ^ 0x80]) + N1[1:]  # cancels the tag domain separator

ctA = encrypt(N1.hex(), "0x" + "00" * 16)  # 32 bytes: [0:16] = rate(Pi(X))
ctB = encrypt(N2.hex(), "0x")              # 16 bytes: tag   = cap(Pi(X))

sys.stderr.write("ctA=%s\nctB=%s\n" % (ctA.hex(), ctB.hex()))

pi_x = bytearray(32)
for i, p in enumerate(RATE):
    pi_x[p] = ctA[i]
for i, p in enumerate(CAP):
    pi_x[p] = ctB[i]

X = permute_inv(bytes(pi_x))               # X = load(N1, K)
key = bytes(X[p] for p in CAP)             # capacity subblocks hold the key
key_hex = "0x" + key.hex()
sys.stderr.write("recovered_key=%s\n" % key_hex)

# Submit the recovered key (single-stage TKR game).
out = call("execute_current_stage", {"stage_payload": {"recovered_key": key_hex}})
sys.stderr.write("RESULT: " + out[:300] + "\n")
PYEOF

# Self-contained attack script; must NOT (re)start the game. Pure stdlib, so a
# bare `uv run python3` (no extra --with packages) suffices.
cat <<'EOF' > /app/attack.sh
#!/bin/bash
uv run python3 /app/spoc_attack.py
EOF
chmod +x /app/attack.sh

echo "SymmetricTargetKeyRecoveryGame" > /app/security_game_choice.txt

echo "Finished writing /app/attack.sh and /app/security_game_choice.txt for T1_spoc."
