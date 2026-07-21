#!/bin/bash
#
# Reference solution for T1_aimer / HashPlaintextRecoveryWithPlaintextReuseAndIVGame.
#
# AIMer v2.1's key generation computes  c = AIM2(iv, p)  where p is the secret
# key (the hidden plaintext) and iv parametrizes the public linear layer. The
# HPR-RIV game reuses one hidden p across unlimited hash-oracle calls while the
# adversary observes the iv used for each call -- exactly the "reused-key"
# model broken by Biryukov-Garcia Fernandez-Udovenko, "Magic Pot:
# Cryptanalysis of full AIM2" (IACR ePrint 2026/903, EUROCRYPT 2026). With
# ~127+ reused-IV (iv, c) pairs the secret key is recovered by linearization.
#
# The Magic Pot attack code lives next to this script in ./aim2_cryptanalysis/
# (an unmodified vendored copy of https://github.com/cryptolu/AIM2_cryptanalysis
# @ commit 5a372f43476a8afe74322a264723c658c883db8a -- see its NOTICE.md). It
# is vendored so this task is fully self-contained with no GitHub dependency
# at run time. All credit for the attack belongs to the upstream authors.

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stage the vendored Magic Pot attack implementation into /app.
mkdir -p /app/aim2_cryptanalysis
cp "$SCRIPT_DIR/aim2_cryptanalysis/aim2.py" \
   "$SCRIPT_DIR/aim2_cryptanalysis/polynomial.py" \
   "$SCRIPT_DIR/aim2_cryptanalysis/halfgcd.py" \
   "$SCRIPT_DIR/aim2_cryptanalysis/attack-aim2-sage.py" \
   "$SCRIPT_DIR/aim2_cryptanalysis/NOTICE.md" \
   /app/aim2_cryptanalysis/

echo "HashPlaintextRecoveryWithPlaintextReuseAndIVGame" > /app/security_game_choice.txt

# Ensure SageMath's Python has the attack's only non-stdlib dependency
# (psutil; tqdm is optional and gracefully degraded by the attack script).
# Done here during the exploration phase -- which has network access -- so it
# persists in the shared container for the verifier's attack.sh run.
sage -pip install --quiet psutil >/dev/null 2>&1 || \
    echo "[solve.sh] warning: could not pre-install psutil; attack.sh will retry"

# --- Emit the self-contained attack script. ------------------------------
cat > /app/attack.sh <<'ATTACK_EOF'
#!/bin/bash
# Self-contained attack: recover the hidden AIM2 preimage via the Magic Pot
# reused-key linearization attack. The HPR-RIV game is already started by the
# verifier; this script must NOT (re)start it.
set -e

CLIENT="/app/game_controller_client.py"
CLI="/app/algorithm_src/cli"
ATTACK_DIR="/app/aim2_cryptanalysis"
PAIRS_FILE="/app/pairs.txt"
WORK_DIR="/app/_attack_work"
mkdir -p "${WORK_DIR}"

# Number of reused-IV pairs. With L>=127 (M=1) the AIM2-I attack runs in well
# under a minute (ePrint 2026/903, Table 4); 256 gives comfortable margin.
NUM_PAIRS=256

# psutil is the attack's only non-stdlib import; pre-installed into the Sage
# env by solve.sh, retried here (idempotent) in case that did not persist.
sage -pip install --quiet psutil >/dev/null 2>&1 || true

client() { python3 "${CLIENT}" "$@"; }
strip0x() { local v="$1"; v="${v#0x}"; v="${v#0X}"; echo "${v,,}"; }

echo "[*] Collecting ${NUM_PAIRS} reused-IV (iv, c) pairs from the hash oracle..."
# Pairs-file format expected by parse_keypairs_file (cryptolu aim2.py): an
# optional leading `sk = <hex>` (a zero placeholder is accepted -- the attack
# does not need the real key to recover it), then repeated `iv =`/`pk =`
# blocks, all natural-byte-order hex (exactly what our cli and the upstream
# simple_keypairs.c emit, and what parse_keypairs_file's bytes.fromhex reads).
printf 'sk = %032x\n\n' 0 > "${PAIRS_FILE}"

FIRST_IV=""
FIRST_C=""
for i in $(seq 1 "${NUM_PAIRS}"); do
    # iv omitted -> oracle generates a fresh random iv and echoes it back;
    # `plaintext` is ignored (the game always hashes the hidden p).
    RESP="$(client --action oracle_query \
        --json '{"oracle_type": "hash", "arguments": {}}')"
    IV_HEX="$(strip0x "$(echo "${RESP}" | python3 -c \
        'import sys,json;print(json.load(sys.stdin)["iv"])')")"
    C_HEX="$(strip0x "$(echo "${RESP}" | python3 -c \
        'import sys,json;print(json.load(sys.stdin)["hash"])')")"
    if [ -z "${IV_HEX}" ] || [ -z "${C_HEX}" ]; then
        echo "[!] Oracle did not return iv/hash: ${RESP}" >&2
        exit 1
    fi
    printf 'iv = %s\npk = %s\n\n' "${IV_HEX}" "${C_HEX}" >> "${PAIRS_FILE}"
    if [ -z "${FIRST_IV}" ]; then FIRST_IV="${IV_HEX}"; FIRST_C="${C_HEX}"; fi
done
echo "[*] Collected pairs into ${PAIRS_FILE}"

# --- Run the Magic Pot attack (pure-SageMath variant). -------------------
# NOTE: with --pairs-file the attack DEDUCES n and ell and rejects explicit
# -n/-l, so we must not pass them. -L defaults to all pairs in the file.
# Use `sage -python` (explicit Python mode): the conda-forge `sage` launcher
# parses unknown flags itself and will not forward --pairs-file to the script,
# whereas `sage -python <script> <args>` runs it as a plain Python program
# (with the Sage library importable) so the script's argparse sees the flags.
echo "[*] Running the Magic Pot reused-key attack (slow step)..."
ATTACK_OUT="${WORK_DIR}/attack_stdout.txt"
# Prefer the Sage conda env's python directly (Sage importable, plain argparse);
# fall back to `sage -python` if the image layout differs.
if [ -x /opt/conda/envs/sage/bin/python ]; then
    SAGE_PY=(/opt/conda/envs/sage/bin/python)
else
    SAGE_PY=(sage -python)
fi
set +e
"${SAGE_PY[@]}" "${ATTACK_DIR}/attack-aim2-sage.py" \
    --pairs-file "${PAIRS_FILE}" --no-progress-bars 2>&1 | tee "${ATTACK_OUT}"
set -e

# --- Recover the key in the game's byte convention. -----------------------
# Format-agnostic + endianness-agnostic: extract every 32-hex token the
# attack printed and validate each (and its byte-reverse) against the LOCAL
# cli -- the exact binary the game oracle uses. A candidate that reproduces a
# known (iv, c) pair *is* the hidden p in the precise convention that
# `recovered_plaintext` is compared against.
echo "[*] Validating recovered candidates against the local oracle binary..."
CANDIDATES="$(grep -oE '[0-9a-fA-F]{32}' "${ATTACK_OUT}" | tr 'A-F' 'a-f' \
    | sort -u)"

reverse_hex() { echo "$1" | fold -w2 | tac | tr -d '\n'; }

WINNER=""
for cand in ${CANDIDATES}; do
    for variant in "${cand}" "$(reverse_hex "${cand}")"; do
        OUT="$(printf 'plaintext: 0x%s\niv: 0x%s\n' "${variant}" "${FIRST_IV}" \
            | "${CLI}" hash 2>/dev/null || true)"
        GOT="$(strip0x "$(echo "${OUT}" | sed -n 's/^hash: //p')")"
        if [ -n "${GOT}" ] && [ "${GOT}" = "${FIRST_C}" ]; then
            WINNER="${variant}"
            break 2
        fi
    done
done

if [ -z "${WINNER}" ]; then
    echo "[!] No recovered candidate reproduced the oracle output." >&2
    exit 1
fi
echo "[*] Recovered hidden plaintext: 0x${WINNER}"

# --- Submit. --------------------------------------------------------------
client --action execute_current_stage \
    --json "{\"stage_payload\": {\"recovered_plaintext\": \"0x${WINNER}\"}}"
echo "[*] Submitted recovered plaintext."
ATTACK_EOF

chmod +x /app/attack.sh
echo "Finished executing all steps in the solve.sh script."
