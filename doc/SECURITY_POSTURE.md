# Security Posture

Last updated: 2026-10-27

Honest limits of `pqlattice` as a **math library**. This is not a threat model
for a full KEM/signature product—that lives with `pqcrypto` and the
application.

Related: [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md), [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md),
[ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. What this package is

- Pure-Dart **lattice / polynomial arithmetic** (NTT, reduce, poly ops).
- Acceleration-default implementations intended to be **correct** under the
  interop rule when used by `pqcrypto`.
- **Not** a cryptographic module, **not** a complete PQC algorithm, **not** a
  FIPS 140 validated component.

---

## 2. Trust boundaries

| Concern | Owner |
|---------|--------|
| Secret key lifetime, wiping buffers | Application + **`zeroize`** (when used) |
| Scheme security (IND-CCA, EUF-CMA, FO) | `pqcrypto` / scheme designers |
| Wire formats, randomness, hashing | `pqcrypto` |
| Math correctness (residues, NTT invertibility) | **`pqlattice`** |
| Side-channel resistance of the full stack | System designers; not guaranteed here |

`pqlattice` must not claim to “securely erase” memory or to provide
portable constant-time execution.

---

## 3. Timing and side channels

| Backend | Posture |
|---------|---------|
| Dart VM JIT / AOT | Source can avoid data-dependent *branches* on secrets where practical; **CPU timing is not guaranteed**. |
| dart2js | JavaScript engines are not constant-time; do not claim CT. |
| dart2wasm | Same caution; SIMD/relaxed paths vary by engine. |

**Allowed wording:** “structured to avoid secret-dependent branches in pure
Dart source where documented.”

**Forbidden wording:** “guaranteed constant-time on all platforms.”

Modular reduce and NTT are **public-parameter** heavy; secret polynomials
still require the scheme layer to handle blinding, rejection sampling, and
zeroization correctly.

---

## 4. Memory and secrets

- Dart GC may **copy** or relocate objects; overwriting a `List` does not
  provide OS-locked secret storage.
- Prefer **`zeroize`** for any buffer that held secret coefficients after use.
- This package may offer hooks or document “caller must zeroize”; it does not
  replace `zeroize`.
- Do not log polynomials, twiddles used with secrets, or intermediate shared
  secrets in examples.

---

## 5. Correctness as a security property

For PQC, **wrong math is a critical failure**. Priorities:

1. Residue correctness and NTT invertibility ([TESTING.md](TESTING.md)).
2. Interop lock so substitution does not create cross-implementation
   decryption/verify failures ([INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md)).
3. Fail closed on bad parameters (wrong length, missing tables).
4. Performance only after 1–3.

---

## 6. Supply chain and API surface

- **MIT** license; no dual-license confusion.
- Minimal runtime dependencies (pure Dart in 0.1.x).
- No `dart:ffi` on the default PQ path (reduces native memory-safety surface;
  does not remove Dart implementation risk).
- Public API should not encourage feeding secrets into debug `toString` on
  hot types in production apps (document; avoid verbose default dumps of full
  polys in library `toString` if feasible).

---

## 7. Vulnerability classes (math-specific)

| Class | Mitigation |
|-------|------------|
| Wrong modulus / mixed rings | `RingParams` checks; tests per profile |
| Wrong basemul (pointwise vs ML-KEM pairs) | Separate APIs + tests |
| Incomplete NTT shipped as complete | Status tags + failing tests if tables empty |
| Reduction bound overflow | [REDUCTION.md](REDUCTION.md) + tests |
| Silent fallback to identity transform | Forbidden by AGENTS.md |

Report security-relevant math bugs via the repository issue tracker with a
minimal failing vector when possible.

---

## 8. Claims checklist before release notes

```text
[ ] No FIPS 140 / CMVP / “certified module” language
[ ] No “implements ML-KEM” as a full algorithm claim
[ ] No portable constant-time guarantee
[ ] No guaranteed secret erasure
[ ] Interop / completeness statements match TESTING evidence
```
