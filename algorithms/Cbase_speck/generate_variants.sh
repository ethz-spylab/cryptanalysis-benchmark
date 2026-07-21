#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# Speck 32/64 has 22 rounds. The base build copies the upstream 64/128 ref and
# applies speck3264.patch to retarget it to 16-bit words / 22 rounds /
# alpha=7,beta=2; the per-variant build below repeats that then reduces the
# round count further. The key schedule still emits all 22 round keys (it is
# forward-only), so only the Encrypt/Decrypt loop bounds need reducing.
#
# Simpler T2 variants: 6, 8, 10. Challenge (C_) ladder: 6, 8, 10, 19
# (same simpler rounds plus the hardest, 19).
VARIANTS=("T2:6" "T2:8" "T2:10" "C:6" "C:8" "C:10" "C:19")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    R_MINUS_1=$((r - 1))

    cat > "$VARIANT_DIR/environment/algorithm_src/build_cli.sh" << BUILDEOF
#!/bin/bash
set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

unzip simon-speck.zip
cp crypto_stream/speck64128ctr/ref/stream.c .
patch -p1 < speck3264.patch

# Reduce to ${r} rounds (full Speck 32/64 has 22 rounds).
sed -i 's/for(i=0;i<22;i++)/for(i=0;i<${r};i++)/' stream.c
sed -i 's/for(i=21;i>=0;i--)/for(i=${R_MINUS_1};i>=0;i--)/' stream.c

gcc -O3 -o cli cli.c stream.c

echo "Build complete. CLI binary created at: \$SCRIPT_DIR/cli"
BUILDEOF
done
