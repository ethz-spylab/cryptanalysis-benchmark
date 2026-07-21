#!/bin/bash
#
# CRUNCH-256 secret-prefix MAC forgery for the HashLengthExtensionForgeryGame.
#
# Weakness (Coban, 2009): CRUNCH is a Merkle-Damgaard hash whose FINAL chaining
# value is emitted directly as the digest, with NO output/finalization transform.
# So MAC_K(m) = H(K || m) is forgeable without K: from one observed
# t = MAC_K(m) = H(K || m) and the public key length |K|, the attacker computes
#     MAC_K(m || glue || S) = H(K || m || glue || S)
# for any suffix S, where glue = pad(K || m). This is the textbook MD
# length-extension forgery; the CRUNCH model below is the one verified
# byte-for-byte against the reference CLI in attack_references/T1_crunch.
#
# Protocol (HashLengthExtensionForgeryGame, 2 stages):
#   Stage 1: execute_current_stage({}) -> learn key_length_bytes = |K|.
#   Stage 2: query the `mac` oracle on a message m chosen so that |K|+|m| is a
#            multiple of CRUNCH's 96-byte message block (the aligned case), then
#            submit (message = m||glue||S, tag = predicted MAC) — a fresh message
#            (never queried) whose tag is prob-1 correct.

# Write the Python attack script (stdlib only: urllib + json; reads the CRUNCH
# constant table const_64.c that build_cli.sh placed in /app/algorithm_src).
cat <<'PYEOF' > /app/crunch_attack.py
#!/usr/bin/env python3
"""CRUNCH-256 length-extension MAC forgery against HashLengthExtensionForgeryGame.

The game is auto-started by the verifier before this script runs, so we never
call start_security_game; we drive the current session's two stages.
"""
import json
import os
import re
import secrets
import sys
import urllib.request

SERVER_URL = "http://game_controller:8000"
SRC_DIR = "/app/algorithm_src"          # build_cli.sh copies const_64.c here
MASK = (1 << 64) - 1

# --- CRUNCH-256 (M64) constants, mirroring crunch_256.c ----------------------
LONGSIZE = 64
HASHLEN = 256
BLOCKSIZE = 1024
K = 128
NBROUND = 256
NE = BLOCKSIZE // LONGSIZE          # 16
NS = HASHLEN // LONGSIZE            # 4
NPM = (LONGSIZE * K) // BLOCKSIZE   # 8
NA = 256
NBE = BLOCKSIZE // K               # 8
DATABLOCK_BYTES = (BLOCKSIZE - HASHLEN) // 8  # 96 bytes of message per block


def idx(a):
    return (LONGSIZE // 8) * (a // (LONGSIZE // 8)) + ((LONGSIZE // 8) - 1) - a % (LONGSIZE // 8)


def load_nbalea(src_dir):
    data = open(os.path.join(src_dir, "const_64.c")).read()
    nums = re.findall(r"0x[0-9a-fA-F]+", data)
    return [int(x, 16) & MASK for x in nums]


class Crunch256:
    def __init__(self, src_dir):
        self.nbalea = load_nbalea(src_dir)
        expected = 2 * 16 * 256 * 16 + 16 - 2
        assert len(self.nbalea) == expected, (len(self.nbalea), expected)

    def _merkle(self, H, mes, nb_merkle):
        nbalea = self.nbalea
        H = H[:]
        message = [0] * NE
        for k in range(NS):
            message[k] = H[k]
        res = [0] * NE
        off = 0
        for _ in range(nb_merkle):
            for k in range(NS):
                res[k] = message[k]
            for k in range(NS, NE):
                message[k] = mes[off + k - NS]
                res[k] = message[k]
            off += (NE - NS)
            a = NE - (128 // LONGSIZE)
            p = 0
            block = 0
            alpha = 1
            for j_round in range(NBROUND):
                i2 = (res[block] >> ((NPM - 1 - p) * NBE)) & (NA - 1)
                i2 = (i2 * alpha) & 0xFF
                i = (message[block] >> ((NPM - 1 - p) * NBE)) & (NA - 1)
                i = (i * alpha) & 0xFF
                aa2 = a + NE * NA * 16 + i2 * NE
                aa = a + i * NE
                for j in range(NE):
                    message[j] ^= nbalea[aa]; aa += 1
                    res[j] ^= nbalea[aa2]; aa2 += 1
                if (j_round & 15) == 15:
                    alpha += 2
                    if (j_round & 127) == 127:
                        a = NE - (128 // LONGSIZE)
                    else:
                        a -= 15 * NA * NE + 128 // LONGSIZE
                else:
                    a += NA * NE
                p += 1
                if p == NPM:
                    block += 1
                    if block == NE:
                        block = 0
                    p = 0
            for j in range(NS):  # SHIFT == 0
                message[j] ^= res[j]
        return message[:NS]

    @staticmethod
    def _longs_to_bytes(longs):
        out = bytearray()
        for v in longs:
            for j in range(8):
                out.append((v >> (8 * j)) & 0xFF)
        return bytes(out)

    @staticmethod
    def _bytes_to_longs(b):
        out = []
        for i in range(0, len(b), 8):
            v = 0
            for j in range(8):
                v |= b[i + j] << (8 * j)
            out.append(v)
        return out

    @staticmethod
    def _full_data_longs(full):
        out = []
        pos = LONGSIZE - 8
        cur = 0
        for byte in full:
            cur |= byte << pos
            pos -= 8
            if pos < 0:
                out.append(cur & MASK)
                cur = 0
                pos = LONGSIZE - 8
        return out

    def _pad_block(self, SizeLeft, leftover, total_bits):
        new_nb_bit = SizeLeft * 8 + 1 + 2 * LONGSIZE
        i = new_nb_bit % (BLOCKSIZE - HASHLEN)
        new_nb_bit += (BLOCKSIZE - HASHLEN) - i
        nbf = new_nb_bit // LONGSIZE
        LeftData = [0] * ((BLOCKSIZE - HASHLEN) // LONGSIZE)
        no_block = 0
        pos = LONGSIZE - 8
        for bi in range(SizeLeft):
            LeftData[no_block] |= leftover[bi] << pos
            pos -= 8
            if pos < 0:
                pos = LONGSIZE - 8
                no_block += 1
        DL = bytearray(self._longs_to_bytes(LeftData))
        mc = bytearray(nbf * 8)
        for bi in range(SizeLeft):
            mc[idx(bi)] = DL[idx(bi)]
        mes = self._bytes_to_longs(bytes(mc))
        nb = (SizeLeft * 8 + 1) // LONGSIZE
        mes[nb] |= 1 << ((LONGSIZE - 1) - ((SizeLeft * 8) % LONGSIZE))
        mes[nbf - 1] = total_bits & MASK
        return mes, nbf

    @staticmethod
    def _init_H_with(nbalea):
        return [nbalea[k] for k in range(NS)]

    def hash(self, msg):
        H = self._init_H_with(self.nbalea)
        n_full = len(msg) // DATABLOCK_BYTES
        full = msg[: n_full * DATABLOCK_BYTES]
        left = msg[n_full * DATABLOCK_BYTES:]
        if n_full > 0:
            H = self._merkle(H, self._full_data_longs(full), n_full)
        mes, nbf = self._pad_block(len(left), left, len(msg) * 8)
        H = self._merkle(H, mes, nbf // (NE - NS))
        hb = bytearray(self._longs_to_bytes(H))
        out = bytearray(HASHLEN // 8)
        for i in range(HASHLEN // 8):
            out[i] = hb[idx(i)]
        return bytes(out)

    # ---- length-extension helpers -------------------------------------------
    @staticmethod
    def out_to_state(digest):
        hb = bytearray(8 * NS)
        for i in range(HASHLEN // 8):
            hb[idx(i)] = digest[i]
        return [int.from_bytes(hb[8 * k:8 * k + 8], "little") for k in range(NS)]

    @staticmethod
    def glue_for_aligned(msg_len_bytes):
        assert msg_len_bytes % DATABLOCK_BYTES == 0
        padmes = [0] * (DATABLOCK_BYTES // 8)
        padmes[0] |= 1 << 63
        padmes[-1] = (msg_len_bytes * 8) & MASK
        glue = bytearray()
        for v in padmes:
            for j in range(7, -1, -1):
                glue.append((v >> (8 * j)) & 0xFF)
        return bytes(glue)

    def extend(self, digest_of_M, len_M_bytes, glue_len_bytes, S):
        H = self.out_to_state(digest_of_M)
        prefix_len = len_M_bytes + glue_len_bytes
        n_full = len(S) // DATABLOCK_BYTES
        full = S[: n_full * DATABLOCK_BYTES]
        left = S[n_full * DATABLOCK_BYTES:]
        if n_full > 0:
            H = self._merkle(H, self._full_data_longs(full), n_full)
        total_bits = (prefix_len + len(S)) * 8
        mes, nbf = self._pad_block(len(left), left, total_bits)
        H = self._merkle(H, mes, nbf // (NE - NS))
        hb = bytearray(self._longs_to_bytes(H))
        out = bytearray(HASHLEN // 8)
        for i in range(HASHLEN // 8):
            out[i] = hb[idx(i)]
        return bytes(out)


# --- game-controller helpers -------------------------------------------------
def http_post(path, data):
    req = urllib.request.Request(
        SERVER_URL + path,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def hexb(h):
    h = h.strip()
    if h[:2].lower() == "0x":
        h = h[2:]
    return bytes.fromhex(h)


def main():
    c = Crunch256(SRC_DIR)

    # Stage 1: learn the public key length |K|.
    r1 = http_post("/execute_current_stage", {"stage_payload": {}})
    n_key = int(r1["stage_result"]["key_length_bytes"])
    print(f"key_length_bytes = {n_key}")

    # Choose m so that |K| + |m| is a positive multiple of the 96-byte block
    # (aligned case -> glue is exactly one block).
    rem = n_key % DATABLOCK_BYTES
    m_len = (DATABLOCK_BYTES - rem) % DATABLOCK_BYTES or DATABLOCK_BYTES
    m = secrets.token_bytes(m_len)
    prefix_len = n_key + m_len            # = |K || m|, a multiple of 96
    assert prefix_len % DATABLOCK_BYTES == 0

    # Stage 2: query the MAC oracle on m -> t = H(K || m).
    rq = http_post(
        "/oracle_query",
        {"oracle_type": "mac", "arguments": {"message": "0x" + m.hex()}},
    )
    tag_hex = rq["oracle_result"].get("tag")
    if tag_hex is None:
        raise RuntimeError(f"mac oracle failed: {rq}")
    t = hexb(tag_hex)

    # Length-extension: forge MAC_K(m || glue || S) without K.
    glue = c.glue_for_aligned(prefix_len)
    S = b"|forged-by-length-extension|"
    forged_msg = m + glue + S            # the part submitted as `message` (after K)
    forged_tag = c.extend(t, prefix_len, len(glue), S)

    # Submit the forgery. `message` (m||glue||S) was never queried (only m was).
    r2 = http_post(
        "/execute_current_stage",
        {"stage_payload": {
            "message": "0x" + forged_msg.hex(),
            "tag": "0x" + forged_tag.hex(),
        }},
    )
    sr = r2.get("stage_result", {})
    print(f"forgery result: {sr}")
    if sr.get("Game won") != "Yes":
        print("FAILURE: forgery was rejected.")
        sys.exit(1)
    print("SUCCESS: length-extension MAC forgery accepted.")


if __name__ == "__main__":
    main()
PYEOF

# Write the attack launcher script (verifier runs this once per round).
cat <<'EOF' > /app/attack.sh
#!/bin/bash
python3 /app/crunch_attack.py
EOF
chmod +x /app/attack.sh

# Write the security game choice.
echo "HashLengthExtensionForgeryGame" > /app/security_game_choice.txt

echo "Finished executing all steps in the solve.sh script."
