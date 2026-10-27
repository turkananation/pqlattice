# NTT Intermediate Bounds (Lazy Reduction)

Last updated: 2026-10-27

This document records the **maximum intermediate magnitude** of each NTT
butterfly in `pqlattice`, per profile, so reviewers can confirm no `int`
overflow and no silent lazy growth.

Related: [REDUCTION.md](REDUCTION.md), [VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md),
[TESTING.md](TESTING.md).

---

## Design decision: no lazy accumulation

Every butterfly in `NttEngine` reduces its two outputs back into `[0, q)`
before the next layer:

- `t = zeta * f[j + len] mod q` — Barrett (or `%` under reference mode, or
  `montMul` under Montgomery mode), result in `[0, q)`.
- `f[j + len] = subFast(f[j], t, q)` — single conditional add, result in `[0, q)`.
- `f[j] = addFast(f[j], t, q)` — single conditional sub, result in `[0, q)`.

The inverse NTT uses the same discipline, then a final per-coefficient
multiply by `invNScale` (`n^{-1} mod q`) via `mulBarrett`/`mul`/Montgomery,
result in `[0, q)`.

**Consequence:** coefficients never grow beyond `[0, q)` between layers.
There is **no lazy-reduction debt** to track for either the Barrett or
Montgomery NTT path. This is stricter than a lazy scheme and removes the need
for a "reduce every k layers" schedule.

---

## Montgomery acceleration

Montgomery-domain NTT is **implemented, tested, and swappable** but **not
default**. Construct `NttEngine` with `montgomeryParams: MontgomeryParams.forQ(q)`
to run the entire transform in Montgomery domain:

- Inputs converted to Montgomery domain on entry via `ModQ.toMont`.
- Twiddles converted to Montgomery domain on the fly via `ModQ.toMont`.
- Butterfly muls use `ModQ.montMul` (Montgomery domain).
- Outputs converted back to normal domain on exit via `ModQ.fromMont`.

Results are **bit-identical** to the Barrett/`-path`; Montgomery is opt-in for
parity testing and measured deployment. Fail-closed: unready `MontgomeryParams`
throws `StateError` at engine construction.

### Montgomery input bounds

`montReduce` accepts `0 <= a < q * R`. Values outside this bound (including
negatives) throw `ArgumentError`. `montMul` requires both operands in `[0, q)`
(Montgomery domain). `toMont` accepts any integer and reduces first.
`fromMont` requires a Montgomery-domain operand in `[0, q)`.

| Profile | q | R | Max `montReduce` input `q*R - 1` | Fits Dart `int`? |
|---------|---|---|----------------------------------|------------------|
| ML-KEM | 3329 | 2^16 | 3329 * 65536 - 1 ≈ 2.2e8 | Yes (trivially) |
| ML-DSA | 8380417 | 2^32 | 8380417 * 4294967296 - 1 ≈ 3.6e16 | Yes (< 9.2e18) |
| FN-DSA-512 | 12289 | 2^16 | 12289 * 65536 - 1 ≈ 8.0e8 | Yes (trivially) |
| FN-DSA-1024 | 12289 | 2^16 | 12289 * 65536 - 1 ≈ 8.0e8 | Yes (trivially) |

The max `montReduce` input `q * R - 1` for ML-DSA ≈ 3.6e16 is well below
Dart `int` max ≈ 9.2e18. No overflow is possible.

`montMul(a, b)` computes `a * b` where both operands are Montgomery-domain
residues in `[0, q)`, so `|a * b| <= q^2`. The intermediate `a * b` before
reduction fits the same bounds as the Barrett table above.

---

## Per-profile bounds

| Profile | q | n | Max value entering a mul | Max `a * b` | Fits Dart `int`? | Notes |
|---------|---|---|--------------------------|-------------|------------------|-------|
| ML-KEM | 3329 | 256 | `q - 1` = 3328 | `3328 * 3328` ≈ 1.1e7 | Yes (trivially) | Incomplete NTT; 7 layers |
| ML-DSA | 8380417 | 256 | `q - 1` = 8380416 | `8380416^2` ≈ 7.0e13 | Yes (< 9.2e18) | Complete NTT; 8 layers |
| FN-DSA-512 | 12289 | 512 | `q - 1` = 12288 | `12288^2` ≈ 1.5e8 | Yes (trivially) | Complete NTT; 9 layers |
| FN-DSA-1024 | 12289 | 1024 | `q - 1` = 12288 | `12288^2` ≈ 1.5e8 | Yes (trivially) | Complete NTT; 10 layers |

Dart `int` is a 63-bit signed integer (max ≈ 9.2e18). The largest product
any butterfly forms is `q^2` for ML-DSA ≈ 7.0e13, roughly **6 orders of
magnitude below** the `int` ceiling. No overflow is possible on the hot path.

---

## Basemul bounds

| Helper | q | Max product | Barrett `maxInputAbs` | Covered? |
|--------|---|-------------|----------------------|----------|
| `mlKemPairs` | 3329 | `q^2` ≈ 1.1e7 | `3329 * 3329` | Yes |
| `mlKemPairsMontgomery` | 3329 | `q^2` ≈ 1.1e7 | N/A (Montgomery domain) | Yes |
| `pointwise` | 3329 | `q^2` ≈ 1.1e7 | `3329 * 3329` | Yes |
| `pointwiseMontgomery` | 3329 | `q^2` ≈ 1.1e7 | N/A (Montgomery domain) | Yes |
| `pointwise` | 12289 | `q^2` ≈ 1.5e8 | `12289 * 12289` | Yes |
| `pointwiseMontgomery` | 12289 | `q^2` ≈ 1.5e8 | N/A (Montgomery domain) | Yes |
| `pointwise` | 8380417 | `q^2` ≈ 7.0e13 | `8380417 * 8380417` | Yes |
| `pointwiseMontgomery` | 8380417 | `q^2` ≈ 7.0e13 | N/A (Montgomery domain) | Yes |

`mulBarrett(a, b, params)` computes `a * b` where both operands are reduced
residues in `[0, q)`, so `|a * b| <= q^2 = maxInputAbs`. Every Barrett
recipe's `maxInputAbs` is exactly `q^2`, so basemul products are always within
the Barrett recipe's documented input bound.

Montgomery-domain basemul (`montMul`) operates on Montgomery-domain residues
in `[0, q)`, so `|a * b| <= q^2` — same bound, same `int` safety.

---

## Montgomery (no longer deferred)

Previously listed as deferred/fail-closed. Now implemented with:
- `montReduce`, `montMul`, `toMont`, `fromMont` in `ModQ` with input-bound validation
- `NttEngine` constructor accepts `montgomeryParams` (opt-in, not default)
- `Basemul.pointwiseMontgomery` / `Basemul.mlKemPairsMontgomery`
- Full edge-case + swap-parity + L3 schoolbook tests in
  `test/montgomery_complete_test.dart`

---

## Test coverage

- `test/barrett_mlkem_test.dart` — Barrett vs `%` on products in `[0, q^2]`.
- `test/barrett_all_profiles_test.dart` — Barrett vs `%` for all three `q`.
- `test/montgomery_complete_test.dart` — Montgomery L1 edge cases,
  fail-closed, NTT swap parity vs Barrett (all profiles), pointwise basemul
  swap parity vs Barrett (all profiles), L3 full pipeline vs schoolbook (all
  profiles).
- `test/ntt_roundtrip_test.dart`, `test/mldsa_ntt_test.dart`,
  `test/fndsa_ntt_test.dart` — NTT roundtrip returns canonical `[0, q)` residues.
- `test/mlkem_ntt_port_test.dart`, `test/mldsa_ntt_test.dart`,
  `test/fndsa_ntt_test.dart` — basemul then inverse equals schoolbook (L3),
  which forces every intermediate through the documented bounds.
