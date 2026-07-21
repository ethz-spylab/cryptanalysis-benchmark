#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALGORITHMS_DIR="$(dirname "$SCRIPT_DIR")"
ALGO_NAME="$(basename "$SCRIPT_DIR")"
NAME="${ALGO_NAME#*_}"

# Simon 32/64 has 32 rounds. The base build copies the upstream 64/128 ref and
# applies simon3264.patch to retarget it to 16-bit words / 32 rounds / z0; the
# per-variant build below repeats that then reduces the round count further.
# The R2 macro performs two rounds per iteration (y-update then x-update). For
# odd r we run the loop for r-1 rounds and emit the trailing y-update as a
# half-round; the decrypt loop is patched symmetrically.
#
# Simpler T2 variants: 10, 14, 18 rounds. Challenge (C_) ladder: 10, 14, 18, 31
# (same simpler rounds plus the hardest, 31 -- odd).
VARIANTS=("T2:10" "T2:14" "T2:18" "C:10" "C:14" "C:18" "C:31")

for entry in "${VARIANTS[@]}"; do
    prefix="${entry%%:*}"
    r="${entry##*:}"
    VARIANT_DIR="$ALGORITHMS_DIR/${prefix}_${NAME}_${r}_rounds"

    cp -r "$SCRIPT_DIR" "$VARIANT_DIR"

    if [ $((r % 2)) -eq 1 ]; then
        R1=$((r - 1))
        R2=$((r - 2))
        cat > "$VARIANT_DIR/environment/algorithm_src/build_cli.sh" << BUILDEOF
#!/bin/bash
set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

unzip simon-speck.zip
cp crypto_stream/simon64128ctr/ref/stream.c .
patch -p1 < simon3264.patch

# Reduce to ${r} rounds (full Simon 32/64 has 32). Odd-round patch: run the
# R2 loop for ${R1} rounds, then emit the trailing y-update as a half-round.
sed -i 's|for(i=0;i<32;i+=2) R2(x,y,key\\[i\\],key\\[i+1\\]);|for(i=0;i<${R1};i+=2) R2(x,y,key[i],key[i+1]); y^=f(x); y^=key[${R1}];|' stream.c
sed -i 's|for(i=31;i>=0;i-=2) R2(y,x,key\\[i\\],key\\[i-1\\]);|y^=key[${R1}]; y^=f(x); for(i=${R2};i>=0;i-=2) R2(y,x,key[i],key[i-1]);|' stream.c

gcc -O3 -o cli cli.c stream.c

echo "Build complete. CLI binary created at: \$SCRIPT_DIR/cli"
BUILDEOF
    else
        R1=$((r - 1))
        cat > "$VARIANT_DIR/environment/algorithm_src/build_cli.sh" << BUILDEOF
#!/bin/bash
set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

unzip simon-speck.zip
cp crypto_stream/simon64128ctr/ref/stream.c .
patch -p1 < simon3264.patch

# Reduce to ${r} rounds (full Simon 32/64 has 32).
sed -i 's|for(i=0;i<32;i+=2)|for(i=0;i<${r};i+=2)|' stream.c
sed -i 's|for(i=31;i>=0;i-=2)|for(i=${R1};i>=0;i-=2)|' stream.c

gcc -O3 -o cli cli.c stream.c

echo "Build complete. CLI binary created at: \$SCRIPT_DIR/cli"
BUILDEOF
    fi
done
