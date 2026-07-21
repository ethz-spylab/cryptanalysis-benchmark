# T1_ranksign — solution status

Target game: **SignatureForgeryGame**. Attack: Debris-Alazard–Tillich (ASIACRYPT
2018) **public-key-only key recovery** on the augmented-LRPC RankSign-I scheme
(no sign-oracle call needed; the SF freshness check is trivially satisfied).

## TL;DR

* **Steps 2–5 of the attack (the actual signature forgery, given the secret
  LRPC support `F'`) are fully implemented and VALIDATED end-to-end against the
  genuine `cli verify`** (returns `valid: true`). Runtime ≈ 55 s
  (`build_structure` ≈ 53 s + `forge` ≈ 2 s). Files: `lib/rs.sage`,
  `lib/decoder.sage`.
* **Step 1 (recover `F'` from the public key) is the sole missing piece.** It is
  a rank-1 MinRank / bilinear Gröbner-basis problem over **GF(2^32)**. The paper
  solves it in Magma in ~20 s. With the tooling available here it does **not**
  fit the 1800 s verifier budget — see "The blocker" below. So the full chain
  does **not** currently reach `reward=1`.

## Field / serialization (verified byte-exact against the reference `cli`)

* Base field `K = GF(2^32) = GF(2)[t]/(t^32+t^7+t^3+t^2+1)` (the `mpfq_2_32`
  modulus). Element ↔ 32-bit int (bit i = t^i), serialized **little-endian**, 4
  bytes.
* Extension `Ext = GF((2^32)^21) = K[X]/IRR`, `IRR = X^21 + a3·X^3 + a0`,
  `a3 = 3685715064`, `a0 = 520681505` (the explicit modulus set in
  `ffi/ffi_elt.c::generateExtension`). Ext element = 21 base coeffs, low degree
  first, 4 bytes LE each → 84 bytes.
* **Public key** (10080 B) = systematic redundant part of `Hpub`: `Hpub` is a
  10×22 matrix over `Ext`, `Hpub = [I_10 | B]` where `B` (10×12) is read from the
  pk, 84 B per entry, row-major `i*12 + (j-10)`.
* **Signature** (1377 B) = FACTORED form: 8 support-basis `Ext` elements
  (8·84=672 B) + (n+t)·r = 22·8 = 176 `K` coordinates (4 B each = 704 B) + 1
  seed byte. `s_i = Σ_j ET[j]·coords[i*8+j]`. **Rank ≤ 8 is automatic** from this
  form, so a forgery only needs `Hpub·s == syndrome` with `s` of rank ≤ 8.
* **Verification** (`crypto_sign_open`): `hash = SHA512(message ‖ seed)`,
  `syndrome = syndromFromHash(hash)` (iterated SHA-512 chain → 10 Ext elements),
  accept iff `Hpub·s == syndrome` AND `rank_K(s) ≤ 8`.

`lib/rs.sage` reproduces all of this exactly (validated: parsing a genuine
signature reproduces the bytes and `verify(...)` matches `cli verify: valid:true`).

## The attack (4 DAT steps)

Shipped params `(n,k,m,d,t,q)=(20,10,21,2,2,2^32)`, `r=8, r2=7, t2=1`.
`Hpub = P·[R|H]·Q` where `H` is the secret LRPC matrix with entries in the
2-dim support `F` (verified by reconstructing `Hpub` from a parsed secret key).

* **Step 1** — find a rank-1 matrix in the projected public code `C_proj_pub`
  (project each Ext coordinate onto `<X^1..X^20>`, dropping the `<1>` part). It
  lifts to a rank-2 codeword `c ∈ Cpub`; `F' = Supp(c)` (2-dim, contains 1).
  Formulated as a bilinear system `Hproj·vec(x⊗y)=0` (188 eqs, x∈K^20, y∈K^22)
  and solved with Gröbner bases. **This is the blocker.**
* **Steps 2–4 + forge** — IMPLEMENTED & VALIDATED in `lib/decoder.sage`
  (`build_structure`, `lrpc_decode_plain`, `forge`):
  1. `C'_pub = {c∈Cpub : c_i∈F'}` (Fq-dim 10, confirmed). `Gc'` = its Ext-span
     (dim 10). `D_code = ker(Gc')` (Ext-dim 12).
  2. Extract from `D_code`: 2 rank-1 codewords with support `<1>` (set `D`,
     dim 2, confirmed) + 10 rank-2 codewords with support ⊆ `F'` (set `D'`,
     dim 14 = n−k+2t, confirmed) → homogeneous weight-2 generator `H'` (12×22).
  3. Column-reduce the 2 rank-1 rows over `Fq` → `P` (22×22 over `Fq`) giving
     `H'·P` with top block diag and bottom-right block `R` (10×20, weight-2,
     support `F'`).
  4. **Sign** for message+seed: `y=(syndrome,0)`, `σ=H'·y`, `f_a=σ[0:2]/diag`,
     `rhs2 = σ[2:12] − C·f_a`. LRPC-decode `R·f_b = rhs2` with the C-style
     erasure (`T = Supp(f_a)`, `S_exp = Supp(rhs2) ⊕ F'·T`,
     `V = f0^{-1}S_exp ∩ f1^{-1}S_exp`, then solve over support `V`). Final
     `e = P·(f_a‖f_b)` has rank ≤ 8 and `Hpub·e = syndrome`. Retry seeds until a
     valid decode (succeeds on seed 0 typically). Serialize to the 1377-byte
     factored form.

  **Validated:** with `F'` taken from a parsed secret key, the produced
  signature is accepted by the real `cli verify` (`valid: true`, rank 7).

## The blocker (Step 1 — why reward=1 is not yet reached here)

Step 1 is a rank-1 MinRank over **GF(2^32)**. Measured in this environment:

* **Sage / Singular Gröbner**: GF(2^32) has no fast table representation in
  Singular, so F4 over it is extremely slow. The structured 24-variable system
  (and the full 30/31-variable system) run **> 1800 s** without finishing
  (random dense bilinear systems of the same size finish in ~180 s, but the
  structured RankSign system has a much higher effective cost). The paper's "20 s"
  is a **Magma** number (Magma's GF(2^32) F4 is far faster); Magma is not
  available.
* **`galois` (JIT numpy GF(2^32)) blind XL/linearization**: GF(2^32) dense
  linear algebra is fast up to ~1700 wide (~120 s) but the MinRank's degree of
  regularity is high — at bidegree (1,2) the system is far from closed
  (null-space dim 54, neither `x` nor `y` determined; `proj(const,Y)` full rank),
  and closing it needs degree ≥4 → matrices far too wide for the budget.
* A second subtlety: a *random* `x_2=α` linear fix is generically **inconsistent**
  (valid α's form a 1-dim curve). The paper's `(x_2−α)(x_2−β)=0` quadratic
  restriction (random α,β) keeps the system consistent and 0-dimensional, but
  still needs a fast Gröbner engine.

`lib/attack_full.sage` contains the COMPLETE correct pipeline (Step 1 via
Gröbner + the validated steps 2–5 + `cli verify`); it is correct but the Step-1
Gröbner exceeds the budget here.

## 2026-07-01 update — deeper Step-1 investigation (still blocked)

Re-attacked Step 1 with the mandate to reconsider the modelling and install
tooling. Results (all validated against a fresh keypair whose ground-truth `F'`
was read from the first 168 B of the sk = the two support elements):

* **Whole forge pipeline re-validated end-to-end on a fresh keypair**: given the
  ground-truth `F'`, `build_structure + forge` → the real `cli verify` returns
  `valid: true` (rank 7), ~55 s. So Steps 2–5 are solid; only Step 1 is missing.
  (Local CLI build needs a `gmp.h` shim + `-DGMP_LIMB_BITS=64`; the task's own
  `build_cli.sh` is unchanged/correct for Docker.)
* **Built a fast GF(2^32) dense linear-algebra primitive** — `lib/gf2lin.c`
  (right-kernel/RREF via the `pclmulqdq` CLMUL intrinsic; `gcc -O3 -mpclmul`).
  It does a ~1770-wide nullspace in ~8 s and a 32k×7315 RREF in ~130 s — orders
  of magnitude faster than `galois`/Sage/`python-flint` for this field. This
  removes the *linear-algebra* bottleneck the previous note blamed.
* **No FOSS fast GF(2^32) solver exists at scale**: `galois` (JIT numpy) chokes
  on random full-rank matrices ≥ ~1500 wide (>280 s); Sage/Singular GF(2^32)
  Gröbner and nullspace are both too slow; **python-flint has NO extension-field
  matrix type** (only `nmod_mat`, prime modulus); `msolve` is prime-field only;
  Magma is proprietary (not freely installable). `pycryptosat` and `python-flint`
  *are* pip/uv-installable at runtime here.
* **The real wall is the DEGREE OF REGULARITY, not the linear algebra.** Every
  first/low-degree modelling plateaus and never pins the linear `x`-coords:
  - plain 2×2-minors, deg-2 linearisation → nullspace **19** (rank 1751/1770);
  - support-minors on the augmented `Q=[[1,w],[z,P]]` (bidegree (1,1)) →
    nullspace **54**;
  - raw bilinear XL bidegree (2,1) → **19**; union (2,1)∪(1,2) → **19**;
  - `y`-elimination → 1292 quadratics purely in `x` (18 vars); XL of those to
    **degree 3 → 19** and **degree 4 → 19** (nullspace is always exactly
    `const + 18 linear`, i.e. the `x_i` are never constrained);
  - relinearising the 19-dim residual → 19 again.
  Diagnostic: within the XL(2,1) nullspace the projection onto `{const, x_i}` has
  full rank 19 — the low-degree linearisation only expresses `y` as a function of
  `x` and does **not** constrain `x` at all. The valid `x` is nonetheless a
  **unique isolated point** (perturbing any single coord makes `rank(M_sub(x))`
  jump 12→13). So the constraint on `x` is intrinsically the corank-1
  determinantal condition (degree ~13) that only collapses via a real F4/F5
  degree-fall (Magma's route) — plain/mutant XL up to degree 4 (the paper's
  claimed d_reg) does **not** reproduce it with these tools.

**Structural fact worth exploiting next**: the rank-≤1 codewords of `C_proj_pub`
form a **10-dim linear subspace** `W = {x⊗y : y∈Y}` with a single common column
support `<x>` (= `proj(z)`, i.e. `W = proj(C'_pub)`). Finding that common column
space is exactly what Step 1 needs; a modelling that targets the *shared*
`x`-direction of a 10-dim rank-1 family (rather than one rank-1 codeword) may
lower the effective degree.

## What a follow-up needs

Only Step 1 needs a faster solver. Any of:
* **A real F4/F5 Gröbner over GF(2^32)** doing the degree fall internally (the
  paper's Magma route, ~20 s). Plain/relinearised/mutant XL up to degree 4 does
  NOT close here; you need genuine S-polynomial reduction with feedback. The
  fast linear-algebra kernel for it already exists (`lib/gf2lin.c`), so a
  from-scratch F4 driver over that primitive is the most plausible FOSS path.
* **Magma** F4 over GF(2^32) (drop-in for the Gröbner call in
  `attack_full.sage`) — but it is licence-locked / not freely installable.
* Once `F'` is recovered, `build_structure(Hpub, F') + forge(...)` from
  `lib/decoder.sage` produces an accepted forgery in ~55 s (already proven).

## New files
* `lib/gf2lin.c` — CLMUL GF(2^32) right-kernel/RREF (stdin binary → stdout
  kernel). Build `gcc -O3 -mpclmul -o gf2lin lib/gf2lin.c`.
* `lib/minors_solve.c` — builds a 2×2-minor deg-2 Macaulay matrix from an affine
  matrix and row-reduces it (both over GF(2^32) via CLMUL).

## Files

* `lib/rs.sage` — field, parsing, `syndromFromHash`, factored-signature
  (de)serialization, `verify` (byte-exact to the reference cli).
* `lib/decoder.sage` — Steps 2–5: `build_structure`, `lrpc_decode_plain`,
  `forge`, `serialize_from_s` (VALIDATED end-to-end given `F'`).
* `lib/attack_full.sage` — complete from-pk pipeline (Step-1 Gröbner + 2–5),
  correct but Step-1 exceeds budget here.
* `lib/xl2.py`, `lib/ycheck.py` — `galois` XL experiments (document the
  XL-degree blocker).
* `solve.sh` — writes `/app/attack.sh` (runs the full pipeline against the game
  controller) and `/app/security_game_choice.txt`.
