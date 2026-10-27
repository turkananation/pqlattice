# Roadmap

Last updated: 2026-10-27

Ordered plan for `pqlattice` without scope creep. Status tags in the README
must match this file.

Related: [AGENT_BRIEF.md](AGENT_BRIEF.md), [CONSUMER_API_AND_MIGRATION.md](CONSUMER_API_AND_MIGRATION.md),
[FN_DSA_MATH.md](FN_DSA_MATH.md), [SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md),
[CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md).

**License:** MIT (same family as `pqcrypto` packaging posture).

---

## 1. North star

A **pure-Dart, acceleration-default** lattice math library that:

1. Implements ring arithmetic for ML-KEM, ML-DSA, and FN-DSA **integer** sides
   with honest completeness tags.
2. Can **replace** `pqcrypto`’s internal poly/NTT math **without** breaking
   OpenSSL / BoringSSL / liboqs / AWS-LC byte-exact interop.
3. Stays web-safe (no FFI on the PQ math path) and claim-boundary clean.

---

## 2. Paths

| Path | Meaning | Owner |
|------|---------|--------|
| **Path A** | Ship usable math APIs + tests; profiles may be scaffold or complete | `pqlattice` |
| **Path B** | Drop-in math backend for `pqcrypto` with L5 intermediate locks | `pqlattice` + `pqcrypto` PR |
| **Path C** | Optional: scheme package consumes FN-DSA integer NTT from here | Future scheme layer |

Fujisaki–Okamoto, sampling, SHAKE, encoding, and full KATs remain **scheme
layer (`pqcrypto`)** forever—not Path A/B math scope.

---

## 3. Milestones

### M0 — Bootstrap (done / in tree)

- Package skeleton, MIT license, claim boundary, AGENTS, API shapes.
- `RingParams`, `ModQ`, `Poly` / `PolyVec`, `NttEngine`, `Basemul`, `KernelMode`.
- Docs: architecture, interop rule, SIMD, VM boundary, SDK tracking.
- Acceleration **default on**.

### M1 — Correct scalar / Barrett core

- Barrett presets for ML-KEM, ML-DSA, FN-DSA `q` values with L1 tests.
- Schoolbook negacyclic + poly ops.
- NTT roundtrip tests structure in place.

**Exit:** L1 green for all presets marked ready; no identity-NTT-as-complete.

### M2 — Profile-complete integer NTTs

| Profile | Exit criteria |
|---------|----------------|
| ML-KEM | Ported zetas/gammas, incomplete NTT, **paired** basemul, L2–L3 green |
| ML-DSA | Tables + NTT + pointwise basemul, L2–L3 green |
| FN-DSA-512 / 1024 | Verified ψ/invN tables, integer NTT, L2–L3 green |

**Exit:** README marks profiles complete only with evidence; table provenance
recorded.

### M3 — Acceleration maturity

- Fused mul-reduce, in-place APIs, packed coeff storage.
- SIMD **shape** + parity tests; still 4-wide + scalar mul until SDK mul lands.
- AOT benches documented ([BENCHMARKS.md](BENCHMARKS.md)).

**Exit:** Default path is accelerated and parity-tested; reference remains oracle.

### M4 — Path B readiness

- L5 intermediate fixtures vs `pqcrypto` for ML-KEM (then ML-DSA).
- Consumer migration doc exercised in a real `pqcrypto` branch.
- No FO or sampling moved into this package.

**Exit:** `pqcrypto` can optionally call `pqlattice` behind a flag without
interop regressions.

### M5 — Upstream Dart SIMD mul (opportunistic)

- Adopt `Int32x4 operator *` per [SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md).
- True pairwise product in basemul/Barrett product steps.
- Fallback for older SDKs.

**Exit:** Measured AOT improvement **or** documented “no win on platform X”;
parity still green.

### M6 — FN-DSA scheme enablement (out of tree)

- Integer math only here; scheme, FFT sampling, Gaussian, encoding elsewhere.
- This milestone is **success of consumers**, not extra scope inside
  `pqlattice`.

---

## 4. Explicit non-goals

| Non-goal | Reason |
|----------|--------|
| Full ML-KEM / ML-DSA / FN-DSA implementation | Belongs in `pqcrypto` |
| FO transform | Scheme layer |
| FIPS 140 / CMVP module | Claim boundary |
| FFI / assembly kernels on default path | Web-safe pure Dart |
| Guaranteed constant-time on JS/Wasm | Reality of those backends |
| Depending on auto-vectorization | VM does not provide it reliably |
| Identity or empty NTT marked complete | Honesty |

---

## 5. README status mapping

| README tag | Meaning |
|------------|---------|
| **scaffold** | Types/API present; tables or tests incomplete |
| **complete** (math) | L2–L3 green + provenance documented for that profile |
| **Path B ready** | L5 lock for that profile |

Do not use “stable crypto” or “production KEM” wording for this package alone.

---

## 6. Dependency posture

| Package | Role |
|---------|------|
| *(none required at runtime in 0.1.x)* | Pure Dart |
| `zeroize` (optional later) | Secret lifetime for coeff buffers—versioned, deliberate |
| `pqcrypto` | Consumer / interop owner—not a dependency of `pqlattice` |

---

## 7. Versioning sketch

| Version | Expectation |
|---------|-------------|
| `0.1.0-dev.*` | API and completeness tags may move; Path B not claimed |
| `0.1.0` | M2 minimum for advertised profiles; tests green |
| `0.2.x` | Path B hooks / migration guides exercised |
| `1.0.0` | Only with stable API + documented interop evidence policy |

Breaking public API before 1.0 is allowed but must be CHANGELOG’d.

---

## 8. Agent rule

When proposing features, map them to a milestone. If they fall under
**non-goals**, reject or move to the scheme package discussion—do not expand
`pqlattice` by stealth.
