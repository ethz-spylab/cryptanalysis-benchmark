# Vendored third-party attack code

The files in this directory are an **unmodified, vendored copy** of the
public Magic Pot AIM2 cryptanalysis implementation, included here so the
reference solution is fully self-contained and independent of GitHub at
task-run time.

- Upstream repository: https://github.com/cryptolu/AIM2_cryptanalysis
- Pinned commit: `5a372f43476a8afe74322a264723c658c883db8a`
- Vendored files: `aim2.py`, `polynomial.py`, `halfgcd.py`,
  `attack-aim2-sage.py` (the pure-SageMath attack variant; the optimized
  `attack-aim2.py` / `ff_rust` Rust path is intentionally not vendored to
  keep the solution dependency-light).
- Associated paper: A. Biryukov, P. García Fernández, A. Udovenko,
  *"Magic Pot: Cryptanalysis of full AIM2 in the standard and
  related-/reused-key settings using new elimination framework"*,
  IACR ePrint 2026/903 (EUROCRYPT 2026).

## Local modifications

The files are verbatim copies of the upstream commit **except** for one
small, clearly-marked compatibility patch in `aim2.py` (search for
`[T1_aimer compatibility patch]`):

- Upstream defines `AIM2_{128,192,256}_Rust` classes unconditionally, and
  their `__init_subclass__` dereferences the optional `ff_rust` Rust
  extension at class-definition time. With only the pure-SageMath attack
  (`attack-aim2-sage.py`) this raises `NameError: ff_rust` at import. The
  patch gates the Rust-only class definitions / registrations on whether
  `import ff_rust` succeeded. The pure-Sage code path
  (`AIM2_*_Sage` / `attack-aim2-sage.py`) is functionally unchanged.

The upstream repository does not ship an explicit license file. These
files are redistributed here solely for academic reproducibility within
this benchmark, with full attribution to the original authors. All credit
for the attack and its implementation belongs to the upstream authors.
