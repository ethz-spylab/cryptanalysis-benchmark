#!/bin/bash
#
# ORANGE-Zest IND-CPA distinguisher solution for the
# SymmetricAdversarialIndistinguishabilityGame.
#
# Weakness (Miguel Montes, OFFICIAL COMMENT: ORANGE, 2019), present in the
# vendored round-1 reference: the buggy `alpha_mult` (missing `else`, so the
# 0x87 carry reduction is never applied) makes the first byte of every
# finite-field-multiply result EVEN. Concretely, when the last plaintext block
# has length > 16, KEYSTREAM BYTE 16 IS ALWAYS EVEN, so for such a message
#     ciphertext[16] & 1  ==  plaintext[16] & 1     (probability 1).
#
# Attack per round of the left-or-right IND game:
#   Stage 1: submit two equal-length (31-byte) messages that are identical
#            except for the low bit of byte 16 (message1[16]&1 = 0,
#            message2[16]&1 = 1). The challenger encrypts message1 if its
#            secret bit b == 0, else message2.
#   Read the challenge ciphertext: guess = ciphertext[16] & 1. Because the
#   keystream byte 16 is even, this equals the low bit of the encrypted
#   message's byte 16, i.e. exactly b.
#   Stage 2: submit `sampled_bit_guess = guess`.
#
# This is a probability-1 distinguisher, so every round is won (offline replay
# of the game accept-logic against the real CLI: 20/20). See
# attack_references/T1_orange/POC_NOTES.md for the keystream-bias derivation.

# Write the Python attack script (stdlib only: urllib + json).
cat <<'PYEOF' > /app/orange_attack.py
#!/usr/bin/env python3
"""Keystream-bias IND-CPA distinguisher for ORANGE-Zest, replaying the 2-stage
SymmetricAdversarialIndistinguishabilityGame against the game controller.

The game is auto-started by the verifier before this script runs, so we never
call start_security_game; we only drive the current session's two stages.
"""
import json
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"

# A single 31-byte block (> 16 bytes) so the keystream-byte-16 bias applies.
# The two candidates are identical except for the low bit of byte 16.
BASE = bytearray(b"\x00" * 31)
M1 = bytearray(BASE)
M1[16] &= 0xFE          # low bit 0  -> selected when the challenger bit b == 0
M2 = bytearray(BASE)
M2[16] |= 0x01          # low bit 1  -> selected when the challenger bit b == 1


def http_post(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def hexb(h):
    if h is None:
        raise RuntimeError("missing ciphertext in stage result")
    h = h.strip()
    if h[:2].lower() == "0x":
        h = h[2:]
    return bytes.fromhex(h)


def main():
    # Stage 1: submit the two candidate messages, receive the challenge ciphertext.
    r1 = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {"stage_payload": {
            "message1": "0x" + M1.hex(),
            "message2": "0x" + M2.hex(),
        }},
    )
    sr = r1.get("stage_result", {})
    if "ciphertext" not in sr:
        raise RuntimeError("unexpected stage-1 result: " + json.dumps(sr))
    ct = hexb(sr["ciphertext"])

    # Keystream byte 16 is even => ciphertext[16] & 1 == plaintext[16] & 1 == b.
    guess = ct[16] & 1
    print(f"ciphertext[16]=0x{ct[16]:02x} -> sampled_bit_guess={guess}")

    # Stage 2: submit the recovered bit.
    r2 = http_post(
        f"{SERVER_URL}/execute_current_stage",
        {"stage_payload": {"sampled_bit_guess": guess}},
    )
    sr2 = r2.get("stage_result", {})
    print(f"stage-2 result: {sr2}")
    if sr2.get("Game won") != "Yes":
        print("FAILURE: distinguisher round was not won.")
        sys.exit(1)
    print("SUCCESS: round won.")


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script (verifier runs this once per round).
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/orange_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice.
echo "SymmetricAdversarialIndistinguishabilityGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
