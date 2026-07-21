#!/bin/bash

# Write the Python attack script
cat <<'PYEOF' > /app/srtpi_attack.py
#!/usr/bin/env python3
"""
SRTPI linearity attack for the AsymmetricDecryptionWithoutPrivateKeyGame.

SRTPI is a linear public-key encryption scheme. This attack exploits that
linearity: by encrypting the zero message many times we can identify the
subspace introduced by randomness, and by encrypting unit-vector messages
we can build a linear map from ciphertext differences to plaintext bits.
Once these matrices are computed, any ciphertext can be decrypted instantly.

Algorithm (from attack.c):
  1. Encrypt zero -> czero (baseline ciphertext)
  2. Encrypt zero 400 more times -> cdiff (randomness differences)
  3. Gaussian-eliminate cdiff to find a basis for the randomness subspace
  4. Encrypt 192 unit-vector messages -> cbits (message-bit contributions)
  5. Project away the randomness subspace from each cbits entry
  6. Gaussian-eliminate cbits (tracking mbits) to get a decryption matrix
  7. For each target ciphertext: XOR with czero, project away randomness,
     read off plaintext bits via the decryption matrix
"""

import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"
MLEN = 24              # Message length in bytes (CRYPTO_MESSAGEBYTES)
CT_BYTES = 512          # Ciphertext length (CRYPTO_MESSAGEBYTES + CRYPTO_BYTES)
CT_BITS = CT_BYTES * 8  # 4096
RANDOMCOVER = 400       # Encryptions of zero to span the randomness subspace


def http_post(url, data):
    """POST JSON and return parsed JSON response."""
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode())


def hex_to_bitint(h):
    """Convert hex string to integer with C-compatible bit layout.

    Byte 0 maps to bits 0-7 (LSB of byte = bit 0), byte 1 maps to
    bits 8-15, etc.  This matches the C code's bit() function:
      int bit(unsigned char *c, int pos) { return 1 & (c[pos/8] >> (pos&7)); }
    """
    if h.startswith(("0x", "0X")):
        h = h[2:]
    b = bytes.fromhex(h)
    result = 0
    for i, v in enumerate(b):
        result |= v << (i * 8)
    return result


def bitint_to_hex(n, num_bytes):
    """Convert integer back to hex string (matching C print_hex output)."""
    parts = []
    for i in range(num_bytes):
        parts.append((n >> (i * 8)) & 0xFF)
    return "0x" + bytes(parts).hex()


def oracle_encrypt(plaintext_hex, pk_hex):
    """Encrypt a plaintext using the game controller's encrypt oracle."""
    result = http_post(
        f"{SERVER_URL}/oracle_query",
        {
            "oracle_type": "encrypt",
            "arguments": {
                "plaintext": plaintext_hex,
                "public-key": pk_hex,
            },
        },
    )
    return result["oracle_result"]["ciphertext"]


def main():
    # ================================================================
    # Stage 0: Retrieve public key and 10 target ciphertexts
    # ================================================================
    print("Stage 0: Getting public key and ciphertexts...")
    resp = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {"stage_payload": {}},
    )
    pk_hex = resp["stage_result"]["public key"]
    targets = resp["stage_result"]["ciphertexts"]
    print(f"  Public key length: {len(pk_hex)} hex chars")
    print(f"  Target ciphertexts: {len(targets)}")

    zero_hex = "0x" + "00" * MLEN

    # ================================================================
    # Phase 1: Encrypt zero to get the baseline ciphertext (czero)
    # ================================================================
    print("\nPhase 1: Baseline encryption of zero message...")
    czero = hex_to_bitint(oracle_encrypt(zero_hex, pk_hex))

    # ================================================================
    # Phase 2: Build the randomness subspace
    #   Encrypt zero RANDOMCOVER times; each ciphertext differs from
    #   czero only due to randomness.
    # ================================================================
    print(f"Phase 2: Building randomness subspace ({RANDOMCOVER} queries)...")
    cdiff = []
    for i in range(RANDOMCOVER):
        ct = hex_to_bitint(oracle_encrypt(zero_hex, pk_hex))
        cdiff.append(ct ^ czero)
        if (i + 1) % 100 == 0:
            print(f"  {i + 1}/{RANDOMCOVER}")

    # Gaussian elimination to find a basis for the randomness subspace
    cdiffpivot = []
    r = 0
    for j in range(CT_BITS):
        for k in range(r, RANDOMCOVER):
            if (cdiff[k] >> j) & 1:
                cdiff[r], cdiff[k] = cdiff[k], cdiff[r]
                for l in range(RANDOMCOVER):
                    if l != r and (cdiff[l] >> j) & 1:
                        cdiff[l] ^= cdiff[r]
                cdiffpivot.append(j)
                r += 1
                break
    print(f"  Randomness subspace dimension: {r}")

    # ================================================================
    # Phase 3: Build the message-bit-to-ciphertext matrix
    #   For each of the 192 message bits, encrypt the corresponding
    #   unit-vector message and project away randomness.
    # ================================================================
    num_bits = MLEN * 8  # 192
    print(f"\nPhase 3: Building message matrix ({num_bits} queries)...")
    mbits = []
    cbits = []
    for i in range(num_bits):
        m = bytearray(MLEN)
        m[i // 8] = 1 << (i & 7)
        ct = hex_to_bitint(oracle_encrypt("0x" + m.hex(), pk_hex))
        c = ct ^ czero
        # Project away randomness subspace
        for k in range(len(cdiffpivot)):
            if (c >> cdiffpivot[k]) & 1:
                c ^= cdiff[k]
        m_int = 0
        for bi, bv in enumerate(m):
            m_int |= bv << (bi * 8)
        mbits.append(m_int)
        cbits.append(c)
        if (i + 1) % 48 == 0:
            print(f"  {i + 1}/{num_bits}")

    # Gaussian elimination on cbits, tracking mbits in parallel
    cbitspivot = []
    r = 0
    for j in range(CT_BITS):
        for k in range(r, num_bits):
            if (cbits[k] >> j) & 1:
                mbits[r], mbits[k] = mbits[k], mbits[r]
                cbits[r], cbits[k] = cbits[k], cbits[r]
                for l in range(num_bits):
                    if l != r and (cbits[l] >> j) & 1:
                        mbits[l] ^= mbits[r]
                        cbits[l] ^= cbits[r]
                cbitspivot.append(j)
                r += 1
                break
    print(f"  Message recovery matrix rank: {r}")

    # ================================================================
    # Phase 4: Decrypt each target ciphertext
    # ================================================================
    print(f"\nPhase 4: Decrypting {len(targets)} target ciphertexts...")
    recovered = []
    for idx, ct_hex in enumerate(targets):
        c = hex_to_bitint(ct_hex) ^ czero
        # Project away randomness
        for k in range(len(cdiffpivot)):
            if (c >> cdiffpivot[k]) & 1:
                c ^= cdiff[k]
        # Recover plaintext using the decryption matrix
        e = 0
        for k in range(len(cbitspivot)):
            if (c >> cbitspivot[k]) & 1:
                c ^= cbits[k]
                e ^= mbits[k]
        pt_hex = bitint_to_hex(e, MLEN)
        recovered.append(pt_hex)
        print(f"  CT {idx + 1}: plaintext = {pt_hex}")

    # ================================================================
    # Stage 1: Submit recovered plaintexts
    # ================================================================
    print("\nStage 1: Submitting recovered plaintexts...")
    resp = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {"stage_payload": {"recovered_plaintexts": recovered}},
    )
    print(f"  Response: {resp}")

    if resp.get("stage_result", {}).get("Game won") == "Yes":
        print("\nSUCCESS: All plaintexts recovered!")
    else:
        print("\nFAILURE: Recovery failed!")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/srtpi_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice
echo "AsymmetricDecryptionWithoutPrivateKeyGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
