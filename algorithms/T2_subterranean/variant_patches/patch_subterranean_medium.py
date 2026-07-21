#!/usr/bin/env python3
"""Subterranean medium variant patch.

Adds a `subterranean_round_no_chi` sibling to `subterranean_round` (the χ
step deleted, iota+theta+pi only) and rewrites the *finalisation* blank
inside `subterranean_SAE_direct_encrypt` and `subterranean_SAE_direct_decrypt`
to be `(rounds-1)` normal duplex calls followed by one no-χ round. This
realises the spec's medium parameter "4 rounds + last χ-stripped".

The other two `subterranean_blank(state, R)` call sites in each function
(the post-K+N init blank and the SAE-wrap variant entry points) keep the
unmodified subterranean_blank — only the per-message finalisation blank
is weakened, matching the recipe in
variant_workfolder/final_fixes_recommendation.md.
"""

import re
import sys

PATH = sys.argv[1]
src = open(PATH).read()

# ---- 1. Inject subterranean_round_no_chi just after subterranean_round. ----
NO_CHI_FN = r"""
/**
* Subterranean round function with the chi step deleted (medium variant).
* Iota + theta + pi only.
*/
void subterranean_round_no_chi(unsigned char state[SUBTERRANEAN_SIZE]){
    unsigned int i;
    unsigned char temp_0, temp_1, temp_2, temp_3, temp_4, temp_5, temp_6, temp_7;
    unsigned char temp_state[SUBTERRANEAN_SIZE];

    /* No chi: copy state into temp_state */
    for(i = 0; i < SUBTERRANEAN_SIZE; i++){
        temp_state[i] = state[i];
    }

    /* Iota step*/
    temp_state[0] ^= 1;

    /* Theta step*/
    temp_0 = temp_state[0] ^ temp_state[3]  ^ temp_state[8];
    temp_1 = temp_state[1] ^ temp_state[4]  ^ temp_state[9];
    temp_2 = temp_state[2] ^ temp_state[5]  ^ temp_state[10];
    temp_3 = temp_state[3] ^ temp_state[6]  ^ temp_state[11];
    temp_4 = temp_state[4] ^ temp_state[7]  ^ temp_state[12];
    temp_5 = temp_state[5] ^ temp_state[8]  ^ temp_state[13];
    temp_6 = temp_state[6] ^ temp_state[9]  ^ temp_state[14];
    temp_7 = temp_state[7] ^ temp_state[10] ^ temp_state[15];
    for(i = 8; i < (SUBTERRANEAN_SIZE-8); i++){
        temp_state[i] = temp_state[i] ^ temp_state[i+3] ^ temp_state[i+8];
    }
    temp_state[i] = temp_state[i] ^ temp_state[i+3] ^ temp_state[0]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[i+3] ^ temp_state[1]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[i+3] ^ temp_state[2]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[i+3] ^ temp_state[3]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[i+3] ^ temp_state[4]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[0]   ^ temp_state[5]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[1]   ^ temp_state[6]; i++;
    temp_state[i] = temp_state[i] ^ temp_state[2]   ^ temp_state[7];
    temp_state[0] = temp_0;
    temp_state[1] = temp_1;
    temp_state[2] = temp_2;
    temp_state[3] = temp_3;
    temp_state[4] = temp_4;
    temp_state[5] = temp_5;
    temp_state[6] = temp_6;
    temp_state[7] = temp_7;

    /* Pi step*/
    for(i = 0; i < (SUBTERRANEAN_SIZE); i++){
        state[i] = temp_state[subterranean_pi_permutation[i]];
    }
}

/**
* Helper: like subterranean_blank(state, r_calls) but the very last
* duplex uses subterranean_round_no_chi (medium variant only).
*/
void subterranean_blank_lastnochi(unsigned char state[SUBTERRANEAN_SIZE], const unsigned char r_calls){
    unsigned char i;
    for(i = 0; i + 1 < r_calls; i++){
        subterranean_duplex(state, NULL, 0);
    }
    /* Final no-chi duplex: round_no_chi + domain-sep bit XOR */
    subterranean_round_no_chi(state);
    state[subterranean_io_bits_0[0]] ^= 1;
}
"""

# Find the closing brace of the subterranean_round function (it sits right
# before subterranean_init).
init_marker = "void subterranean_init"
idx = src.find(init_marker)
assert idx != -1, "subterranean_init not found"
src = src[:idx] + NO_CHI_FN + "\n" + src[idx:]


# ---- 2. In each of the SAE direct encrypt/decrypt functions, replace ----
# the *second* subterranean_blank(state, N) call (the finalisation blank
# before subterranean_squeeze) with subterranean_blank_lastnochi.
def patch_finalisation(src, fn_name):
    fn_start = src.find("void " + fn_name)
    if fn_start == -1:
        fn_start = src.find("int " + fn_name)
    assert fn_start != -1, f"{fn_name} not found"
    # Find function body extent: braces matching from the opening '{'.
    brace_start = src.find("{", fn_start)
    depth = 0
    body_end = brace_start
    for j in range(brace_start, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                body_end = j
                break
    body = src[brace_start : body_end + 1]
    # The finalisation blank is the LAST subterranean_blank(...) call in the body.
    matches = list(re.finditer(r"subterranean_blank\(state,\s*\d+\);", body))
    assert matches, f"no subterranean_blank in {fn_name}"
    last = matches[-1]
    new_body = (
        body[: last.start()]
        + last.group(0).replace("subterranean_blank", "subterranean_blank_lastnochi")
        + body[last.end() :]
    )
    return src[:brace_start] + new_body + src[body_end + 1 :]


src = patch_finalisation(src, "subterranean_SAE_direct_encrypt")
src = patch_finalisation(src, "subterranean_SAE_direct_decrypt")

open(PATH, "w").write(src)
