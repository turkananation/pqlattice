# Testing Strategy

Last updated: 2026-10-27

This document is the **correctness contract** for `pqlattice`. Agents and
reviewers must treat the oracle hierarchy and merge gates as binding.

Related: [AGENTS.md](../AGENTS.md), [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md),
[SIMD.md](SIMD.md), [REDUCTION.md](REDUCTION.md), [TABLE_PROVENANCE.md](TABLE_PROVENANCE.md).

---

## 1. Principles

1. **Scalar / reference is truth** for algebraic identity. Accelerated paths
   must match it on the residues the public API promises.
2. **Interop wins.** When a path is intended to replace `pqcrypto` math,
   parity with that path (or shared intermediate vectors) is required before
   defaulting to it—see [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md).
3. **No silent fallbacks** that change mathematics (wrong basemul shape, empty
   twiddle tables, identity NTT labeled complete).
4. **Fail closed** in tests: missing tables, wrong `n`/`q`, or parity failure
   must fail the test—not soft-skip production claims.
5. **This package does not own full-scheme KATs.** Those live in `pqcrypto`.
   We own **math-layer** properties and optional intermediate-value locks.

---

## 2. Oracle hierarchy (bottom → top)

| Level | What | Role | Typical location |
|-------|------|------|------------------|
| **L0 — Schoolbook** | Negacyclic product over \(\mathbb{Z}_q[x]/(x^n\pm 1)\) with plain `%` or reference reduce | Ground truth for small \(n\) and structure tests | `test/ring_mul_test.dart` |
| **L1 — Field reduce** | Barrett / Montgomery / freeze vs reference `mod q` | Every accelerated reduce must match L1 on random + edge coeffs | `test/barrett_*.dart`, `mod_q_test.dart`, `mod_strategy_test.dart` |
| **L2 — NTT roundtrip** | `iNTT(NTT(a)) ≡ a` (canonical residues) for each profile | Twiddles + invN + scaling correct | `test/ntt_roundtrip_test.dart`, profile NTT tests |
| **L3 — NTT × basemul vs schoolbook** | Domain mul then inverse equals schoolbook product | End-to-end ring mul for that profile | `test/ring_mul_test.dart`, profile tests |
| **L4 — SIMD parity** | SIMD-shaped kernel ≡ optimized scalar on fixed + random vectors | Required before treating SIMD as capable | `test/simd_pointwise_parity_test.dart` |
| **L5 — Intermediate lock** | Vectors / poly ops match `pqcrypto` (or published ref) on named fixtures | Required before Path B substitution | `test/` or `tool/` fixtures, clearly labeled |
| **L6 — Scheme KAT / interop** | Full ML-KEM / ML-DSA / FN-DSA bytes | **`pqcrypto` only** — not a `pqlattice` merge gate |

Always implement and green **L0–L3** for a profile before calling that
profile’s NTT “complete.” L4 before defaulting SIMD for that op. L5 before
telling consumers to switch math backends.

---

## 3. Profile matrix

Every **claimed-complete** ring profile needs:

| Check | ML-KEM | ML-DSA | FN-DSA-512 | FN-DSA-1024 |
|-------|--------|--------|------------|-------------|
| `RingParams` preset | ✓ | ✓ | ✓ | ✓ |
| Barrett and/or Mont params | ✓ | ✓ | ✓ | ✓ |
| Twiddle tables length + invN | ✓ | ✓ | ✓ | ✓ |
| NTT roundtrip | ✓ | ✓ | ✓ | ✓ |
| Correct basemul shape | pairs | pointwise | pointwise | pointwise |
| SIMD parity (if SIMD claims that op) | as implemented | as implemented | as implemented | as implemented |

Incomplete profiles must be labeled **scaffold** in README and must not be
the default in examples without a warning.

---

## 4. Required tests by area

### Modular arithmetic

- Random coeffs in a range larger than \(q\); compare Barrett/Mont to reference.
- Edges: `0`, `q-1`, `q`, `q+1`, `-1`, products near documented lazy bounds.
- `addFast` / `subFast` then force reduce; result in canonical range if API
  promises it.
- Strategy selection: accelerated path selected by default; reference path
  still available for oracles (`mod_strategy_test.dart`).

### Polynomials / vectors

- In-place vs allocating APIs leave the same mathematical result.
- Length / degree checks throw (fail closed) on mismatch.
- `PolyVec` ops consistent with per-poly ops.

### NTT

- Roundtrip for each complete profile.
- Reject or fail if tables empty while API claims real NTT.
- ML-KEM: **paired** basemul, not naive pointwise (regression test).
- FN-DSA: integer NTT only; document non-goals (FFT, Gaussian) in tests’ comments only if helpful—do not implement scheme sampling here.

### SIMD

- Bit-identical (or residue-identical per public contract) to scalar for the
  same `KernelMode` contract.
- Run under **AOT** when making speed claims; CI at least JIT + one AOT job
  when available.

### Coeff storage

- `CoeffBuffer` / `Int16List` / `Int32List` layout matches documented width
  (`coeff_buffer_test.dart`).

---

## 5. Merge gates (minimum)

A PR that touches math **must not merge** unless:

```text
[ ] dart analyze clean on changed packages
[ ] dart test  (all existing tests green)
[ ] If reduction touched: barrett_* + mod_* green
[ ] If NTT/tables touched: ntt_roundtrip + that profile’s NTT test green
[ ] If basemul shape touched: ring_mul / mlkem pairs regression green
[ ] If SIMD touched: simd_pointwise_parity green
[ ] No new “FIPS validated” / scheme-KAT claims in docs
[ ] CHANGELOG note if public behavior or default kernel changed
```

Optional but expected for Path B work:

```text
[ ] L5 intermediate fixture vs pqcrypto on at least one profile
```

---

## 6. Property ideas (extend over time)

- Random poly: `reduce(a + b) = reduce(reduce(a) + reduce(b))` (as defined).
- NTT linearity (mod q) on small random inputs.
- Inverse NTT left/right inverse on the supported domain.
- Lazy growth: after \(k\) butterflies without full reduce, magnitude ≤ bound
  in [REDUCTION.md](REDUCTION.md).

Prefer deterministic seeds in CI for reproducibility.

---

## 7. What not to test here

| Out of scope | Owner |
|--------------|--------|
| Full FIPS 203/204/206 KATs | `pqcrypto` |
| FO transform, sampling, SHAKE, encoding | `pqcrypto` |
| OpenSSL / liboqs process harnesses | `pqcrypto` CI |
| OS-level memory disclosure | `zeroize` + platform |

---

## 8. Naming and layout conventions

- `*_test.dart` under `test/`.
- Profile-specific: `mlkem_*`, `mldsa_*`, `fndsa_*`.
- Parity: `*_parity_test.dart`.
- Fixtures for L5: `test/fixtures/` or `tool/interop/` with README stating
  source and non-KAT status.

---

## 9. Agent checklist

```text
Before claiming a profile complete:
  [ ] L1–L3 green for that profile
  [ ] Tables documented in TABLE_PROVENANCE.md
  [ ] README status row updated (scaffold → complete only with evidence)

Before changing default KernelMode behavior:
  [ ] L4 green if SIMD involved
  [ ] INTEROP rule acknowledged in PR text
```
