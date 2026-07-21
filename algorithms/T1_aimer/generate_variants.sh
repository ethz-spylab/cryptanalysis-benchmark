#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

VARIANTS=(
    "T1:150:HashPlaintextRecoveryWithPlaintextReuseAndIV150IVLimitGame:keep"
    "T1:25:HashPlaintextRecoveryWithPlaintextReuseAndIV25IVLimitGame:todo"
    "T1:15:HashPlaintextRecoveryWithPlaintextReuseAndIV15IVLimitGame:todo"
    "T1:11:HashPlaintextRecoveryWithPlaintextReuseAndIV11IVLimitGame:todo"
)

BASE_GAME="HashPlaintextRecoveryWithPlaintextReuseAndIVGame"

for entry in "${VARIANTS[@]}"; do
    IFS=':' read -r prefix budget game mode <<< "$entry"

    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${budget}_ivs"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"
    # Drop the nested copy of this script so it is never re-run for the variant.
    rm -f "$VARIANT_DIR/generate_variants.sh"

    # Restrict the variant to the IV-limited game only.
    cat > "$VARIANT_DIR/environment/possible_security_games.yml" << YMLEOF
security_games:
  - ${game}
YMLEOF

    case "$mode" in
        keep)
            SOLVE="$VARIANT_DIR/solution/solve.sh"
            sed -i "s/${BASE_GAME}/${game}/g" "$SOLVE"
            sed -i "s/^NUM_PAIRS=256$/NUM_PAIRS=${budget}/" "$SOLVE"
            sed -i \
                "s/256 gives comfortable margin\./${budget} fits the ${budget}-IV query budget and stays above the L>=127 minimum./" \
                "$SOLVE"
            ;;
        todo)
            # No published attack fits this query budget; leave a placeholder.
            rm -rf "$VARIANT_DIR/solution"
            mkdir -p "$VARIANT_DIR/solution"
            cat > "$VARIANT_DIR/solution/TODO.md" << TODOEOF
# No reference solution yet
TODOEOF
            ;;
        *)
            echo "Unknown solution mode: ${mode}" >&2
            exit 1
            ;;
    esac
done
