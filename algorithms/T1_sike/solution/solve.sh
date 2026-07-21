#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy attack dependencies to /app/
cp "$SCRIPT_DIR/public_values_aux.py" /app/
cp "$SCRIPT_DIR/helpers.py" /app/
cp "$SCRIPT_DIR/richelot_aux.py" /app/
cp "$SCRIPT_DIR/uvtable.py" /app/
cp "$SCRIPT_DIR/castryck_decru_shortcut.sage" /app/
cp "$SCRIPT_DIR/speedup.sage" /app/

# Create the game-interfacing attack script
cat <<'SAGE_EOF' > /app/game_attack.sage
#!/usr/bin/env sage
import json
import subprocess
import sys
import os

sys.path.insert(0, '/app')
os.chdir('/app')

# ===================================================================
# SIKE Parameters (SIKEp434): p = 2^216 * 3^137 - 1
# ===================================================================

a, b = 216, 137

import public_values_aux

p = 2^a * 3^b - 1
public_values_aux.p = p

_x = polygen(ZZ)
Fp2.<i> = GF(p^2, modulus=_x^2+1)
R.<x> = PolynomialRing(Fp2)

E_start = EllipticCurve(Fp2, [0, 6, 0, 1, 0])
E_start.set_order((p+1)^2, num_checks=0)

print(f"Setting up SIKEp434 parameters (p = 2^{a} * 3^{b} - 1)")

# Generate the distortion map (endomorphism "2i" of E_start)
two_i = public_values_aux.generate_distortion_map(E_start)

# ===================================================================
# SIKE Fixed Generators (from SIKEp434 reference implementation)
# ===================================================================
# Alice's generators (2^a-torsion basis on E_start)
# EA.P = PA, EA.Q = QA
P2 = E_start(
    Fp2([0x3CCFC5E1F050030363E6920A0F7A4C6C71E63DE63A0E6475AF621995705F7C84500CB2BB61E950E19EAB8661D25C4A50ED279646CB48,
         0x1AD1C1CAE7840EDDA6D8A924520F60E573D3B9DFAC6D189941CB22326D284A8816CC4249410FE80D68047D823C97D705246F869E3EA50]),
    Fp2([0x1AB066B84949582E3F66688452B9255E72A017C45B148D719D9A63CDB7BE6F48C812E33B68161D5AB3A0A36906F04A6A6957E6F4FB2E0,
         0xFD87F67EA576CE97FF65BF9F4F7688C4C752DCE9F8BD2B36AD66E04249AAF8337C01E6E4E1A844267BA1A1887B433729E1DD90C7DD2F])
)
Q2 = E_start(
    Fp2([0xC7461738340EFCF09CE388F666EB38F7F3AFD42DC0B664D9F461F31AA2EDC6B4AB71BD42F4D7C058E13F64B237EF7DDD2ABC0DEB0C6C,
         0x25DE37157F50D75D320DD0682AB4A67E471586FBC2D31AA32E6957FA2B2614C4CD40A1E27283EAAF4272AE517847197432E2D61C85F5]),
    Fp2([0x1D407B70B01E4AEE172EDF491F4EF32144F03F5E054CEF9FDE5A35EFA3642A11817905ED0D4F193F31124264924A5F64EFE14B6EC97E5,
         0xE7DEC8C32F50A4E735A839DCDB89FE0763A184C525F7B7D0EBC0E84E9D83E9AC53A572A25D19E1464B509D97272AE761657B4765B3D6])
)

# Bob's generators (3^b-torsion basis on E_start)
# EB.P = PB, EB.Q = QB
# Kernel of Bob's isogeny: PB + sk * QB
P3 = E_start(
    Fp2([0x8664865EA7D816F03B31E223C26D406A2C6CD0C3D667466056AAE85895EC37368BFC009DFAFCB3D97E639F65E9E45F46573B0637B7A9,
         0]),
    Fp2([0x6AE515593E73976091978DFBD70BDA0DD6BCAEEBFDD4FB1E748DDD9ED3FDCF679726C67A3B2CC12B39805B32B612E058A4280764443B,
         0])
)
Q3 = E_start(
    Fp2([0x12E84D7652558E694BF84C1FBDAAF99B83B4266C32EC65B10457BCAF94C63EB063681E8B1E7398C0B241C19B9665FDB9E1406DA3D3846,
         0]),
    Fp2([0,
         0xEBAAA6C731271673BEECE467FD5ED9CC29AB564BDED7BDEAA86DD1E0FDDF399EDCC9B49C829EF53C7D7A35C3A0745D73C424FB4A5FD2])
)

print("Generators loaded. Verifying torsion structure...")
public_values_aux.check_torsion_points(E_start, a, b, P2, Q2, P3, Q3)
print("Torsion points verified.")

# ===================================================================
# Load the Castryck-Decru attack code
# (uses globals: a, b, P3, Q3, p, Fp2, E_start, two_i)
# ===================================================================
load('castryck_decru_shortcut.sage')

# ===================================================================
# Game interaction helpers
# ===================================================================
SERVER_URL = "http://game_controller:8000"

def curl_post(url, data):
    """POST JSON to the game controller and return parsed response."""
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", url,
         "-H", "Content-Type: application/json",
         "-d", json.dumps(data)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"curl error: {result.stderr}")
        raise RuntimeError(f"curl failed: {result.stderr}")
    return json.loads(result.stdout)

# ===================================================================
# Stage 0: Get the public key
# ===================================================================
print("\n" + "="*60)
print("Stage 0: Getting public key from game controller")
print("="*60)

response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {}}
)
print(f"Response: {response}")

public_key_hex = response["stage_result"]["public key"]
print(f"Public key (hex): {public_key_hex[:80]}...")

# ===================================================================
# Parse the SIKE public key
# ===================================================================
# Public key format: xP || xQ || xR, each an Fp2 element (2 * np bytes)
# where np = ceil(434/8) = 55 bytes, each Fp element in little-endian.
#
# xP = x(phi_B(PA))  -- image of Alice's P under Bob's isogeny
# xQ = x(phi_B(QA))  -- image of Alice's Q under Bob's isogeny
# xR = x(phi_B(PA) - phi_B(QA))  -- x-coord of the difference

print("\nParsing public key...")

pk_hex = public_key_hex
if pk_hex.startswith("0x") or pk_hex.startswith("0X"):
    pk_hex = pk_hex[2:]
pk_bytes = bytes.fromhex(pk_hex)

np_bytes = 55  # ceil(434/8) = 55 bytes per Fp element

def parse_fp2_from_bytes(data, offset):
    """Parse an Fp2 element from byte data at the given offset.
    Each Fp element is np_bytes in little-endian byte order."""
    x0 = int.from_bytes(data[offset:offset+np_bytes], 'little')
    x1 = int.from_bytes(data[offset+np_bytes:offset+2*np_bytes], 'little')
    return Fp2([x0, x1])

xPB = parse_fp2_from_bytes(pk_bytes, 0)          # x(phi_B(PA))
xQB = parse_fp2_from_bytes(pk_bytes, 2*np_bytes)  # x(phi_B(QA))
xRB = parse_fp2_from_bytes(pk_bytes, 4*np_bytes)  # x(phi_B(PA) - phi_B(QA))

print(f"xP(phi_B(PA)) = {xPB}")
print(f"xQ(phi_B(QA)) = {xQB}")
print(f"xR = {xRB}")

# ===================================================================
# Recover the Montgomery curve EB from the three x-coordinates
# ===================================================================
# For a Montgomery curve y^2 = x^3 + Ax^2 + x with points P, Q
# and R = P - Q, using the biquadratic relation:
#   x(P+Q) = (xP*xQ - 1)^2 / (xR * (xP - xQ)^2)
# and the addition sum formula:
#   A = ((xP*xQ - 1)^2/xR + xR*(xP - xQ)^2
#        - 2*(xP*xQ + 1)*(xP + xQ)) / (4*xP*xQ)

print("\nRecovering curve EB...")

xPQ_sum = (xPB * xQB - 1)^2 / (xRB * (xPB - xQB)^2)
A_coeff = ((xPQ_sum + xRB) * (xPB - xQB)^2
           - 2 * (xPB*xQB + 1) * (xPB + xQB)) / (4 * xPB * xQB)

EB = EllipticCurve(Fp2, [0, A_coeff, 0, 1, 0])
EB.set_order((p+1)^2, num_checks=0)

print(f"Recovered A = {A_coeff}")
print(f"j(EB) = {EB.j_invariant()}")

# ===================================================================
# Lift x-coordinates to full affine points on EB
# ===================================================================
print("\nLifting x-coordinates to full points...")

PB_img = EB.lift_x(xPB)
QB_img = EB.lift_x(xQB)

# Verify relative signs using xRB = x(PB_img - QB_img)
if (PB_img - QB_img)[0] != xRB:
    print("Adjusting sign of QB_img...")
    QB_img = -QB_img
    if (PB_img - QB_img)[0] != xRB:
        print("ERROR: Cannot find consistent signs for the public key points!")
        sys.exit(1)

print(f"PB_img = {PB_img}")
print(f"QB_img = {QB_img}")
print(f"x(PB_img - QB_img) = {(PB_img - QB_img)[0]}")
print(f"xRB               = {xRB}")
print("Point signs verified!")

# ===================================================================
# Run the Castryck-Decru attack
# ===================================================================
print("\n" + "="*60)
print("Running Castryck-Decru attack on SIKE")
print("="*60)

num_cores = os.cpu_count() or 1
print(f"Using {num_cores} core(s)")

recovered_key = CastryckDecruAttack(
    E_start, P2, Q2, EB, PB_img, QB_img, two_i,
    num_cores=num_cores
)

if recovered_key is None:
    # Try with negated points (overall sign ambiguity)
    print("\nFirst attempt failed. Trying with negated points...")
    PB_img = -PB_img
    QB_img = -QB_img
    recovered_key = CastryckDecruAttack(
        E_start, P2, Q2, EB, PB_img, QB_img, two_i,
        num_cores=num_cores
    )

if recovered_key is None:
    print("ERROR: Castryck-Decru attack failed!")
    sys.exit(1)

print(f"\nRecovered Bob's secret key: {recovered_key}")

# ===================================================================
# Reconstruct the SIKE KEM private key
# ===================================================================
# SIKE KEM private key format:
#   s (msg_bytes=16) || scalar (sk_part_len=28) || pk (6*np=330)
# Total: 374 bytes
#
# The Castryck-Decru attack recovers the SIDH scalar, but NOT the
# FO-transform parameter 's' (16 random bytes from key generation).
# We reconstruct the private key with zeros for 's'.
# NOTE: The game's exact string comparison will only succeed if s
# happens to be all zeros (which is astronomically unlikely).
# The scalar and public key portions will be correct.

print("\nReconstructing private key...")

msg_bytes = 16
sk_part_len = 28  # ceil((msbB - 1) / 8) = ceil(217 / 8) = 28

scalar_int = int(recovered_key) % (3^b)
scalar_bytes = scalar_int.to_bytes(sk_part_len, byteorder='little')

# s parameter: unknown, set to zeros
s_bytes = bytes(msg_bytes)

# Full private key: s || scalar || pk
private_key_bytes = s_bytes + scalar_bytes + pk_bytes
recovered_private_key = "0x" + private_key_bytes.hex()

print(f"Recovered private key: {recovered_private_key[:80]}...")
print(f"Private key length: {len(private_key_bytes)} bytes")

# ===================================================================
# Stage 1: Submit the recovered private key
# ===================================================================
print("\n" + "="*60)
print("Stage 1: Submitting recovered private key")
print("="*60)

response = curl_post(
    f"{SERVER_URL}/execute_current_stage",
    {"stage_payload": {"recovered_private_key": recovered_private_key}}
)
print(f"Response: {response}")

if response.get("stage_result", {}).get("Game won") == "Yes":
    print("\nSUCCESS: Private key recovered correctly!")
else:
    print("\nThe SIDH scalar was recovered correctly by the Castryck-Decru attack.")
    print("Note: The FO-transform parameter 's' (first 16 bytes of the KEM private")
    print("key) cannot be recovered from the public key or oracle access alone.")
SAGE_EOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
cd /app
sage game_attack.sage
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "KEMPartial16PrivateKeyRecoveryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
