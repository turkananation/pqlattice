# AGENTS.md — Mission-Critical Development Rules

Last updated: 2026-10-27

This file is **binding** for every human and automated agent working in
`pqlattice`. It exists to prevent correctness failures, silent math bugs,
scope creep, and security-adjacent mistakes in a pure-Dart lattice arithmetic
library that will underpin post-quantum scheme packages.

Read in order before changing code:

1. This file (`AGENTS.md`)
2. [doc/CLAIM_BOUNDARY.md](doc/CLAIM_BOUNDARY.md)
3. [doc/API.md](doc/API.md)
4. [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md)
5. [doc/AGENT_BRIEF.md](doc/AGENT_BRIEF.md) (paths and gates)
6. [doc/VM_COMPILER_BOUNDARY.md](doc/VM_COMPILER_BOUNDARY.md)
7. [doc/TESTING.md](doc/TESTING.md) — oracle hierarchy and merge gates
8. [doc/REDUCTION.md](doc/REDUCTION.md) when touching Barrett/Montgomery/lazy bounds
9. [doc/SDK_SIMD_TRACKING.md](doc/SDK_SIMD_TRACKING.md) / [doc/SDK_CONSTRAINTS.md](doc/SDK_CONSTRAINTS.md) when touching SIMD or SDK bounds
10. [doc/ROADMAP.md](doc/ROADMAP.md) before new features (reject non-goals)
11. [doc/SECURITY_POSTURE.md](doc/SECURITY_POSTURE.md) before external security wording
12. [doc/CONSUMER_API_AND_MIGRATION.md](doc/CONSUMER_API_AND_MIGRATION.md) / [doc/FN_DSA_MATH.md](doc/FN_DSA_MATH.md) / [doc/TABLE_PROVENANCE.md](doc/TABLE_PROVENANCE.md) when touching consumer, FN-DSA, or tables

If two documents appear to conflict, **claim boundary and this file win** over
convenience.

---


## 0. Primary external rule (pqcrypto interop)

`pqcrypto` is **byte-exact interoperable** with **OpenSSL, BoringSSL, liboqs, and
AWS-LC**, while following the relevant **FIPS algorithm** specifications
(FIPS 203 / 204 / …).

Math in this package that will be consumed by `pqcrypto` **must not break that
byte agreement**. Prefer porting and parity with the existing `pqcrypto` path
over novel formulations. Full rule: [doc/INTEROP_AND_FIPS_RULE.md](doc/INTEROP_AND_FIPS_RULE.md).

If performance conflicts with interop: **interop wins**.

## 0.1 Acceleration is the product

`pqlattice` exists to **accelerate** lattice math. Barrett, optimized NTT/basemul,
and SIMD (when capable) are **default / first-class**, not opt-in. Reference `%`
and schoolbook are for tests. Full policy: [doc/ACCELERATION.md](doc/ACCELERATION.md).
Interop still constrains correctness: [doc/INTEROP_AND_FIPS_RULE.md](doc/INTEROP_AND_FIPS_RULE.md).

## 1. Mission

Deliver **correct, auditable, pure-Dart** ring / NTT / modular arithmetic with:

- Deterministic results for the same inputs
- Explicit domain and ring binding (no silent mix of profiles)
- Accelerated path is default and must be correct; reference path for oracles; SIMD parity-tested when enabled
- Zero overclaim on schemes, module validation, or hard timing guarantees
- A surface that `pqcrypto` (and future FN-DSA modules) can adopt without rewriting algebra

**Correctness beats performance.** Ship a slow correct NTT before a fast wrong one.

---

## 2. Non-negotiable invariants

### 2.1 Mathematical

1. **Ring binding** — Every `Poly` / `NttEngine` / `Basemul` call must agree on
   `q` and `n`. Mismatch → throw; never coerce.
2. **Profile-correct products**
   - ML-KEM → `Basemul.mlKemPairs` only (never substitute `pointwise`)
   - ML-DSA / FN-DSA integer → `Basemul.pointwise`
3. **Domain honesty** — Document whether values are normal-order or NTT-domain.
   Do not apply schoolbook formulas to NTT-domain coeffs without conversion.
4. **Reduction** — Public outputs of reduce / final NTT layers land in a
   documented representative system (prefer \([0,q)\) unless a function is
   explicitly “centered”).
5. **No `BigInt` on hot paths** — NTT, basemul, Barrett/Montgomery loops use
   `int` / typed data only. Document intermediate magnitude bounds when using
   lazy reduction.
6. **Empty zeta tables** — While `NttParams.zetas` is empty, NTT must remain a
   **documented identity or fail closed**; never invent fake twiddles.
7. **Fail closed on deferred math** — Montgomery not ready → throw, do not
   silently fall through to wrong domain arithmetic.
8. **Oracle discipline** — `RingMul.schoolbookNegacyclic` is the algebraic
   reference for products. New NTT mul paths must match it (or a checked
   intermediate corpus) before optimization.

### 2.2 Engineering

1. **Pure Dart** — No `dart:ffi`, no platform channels, no conditional imports
   that break web for core math.
2. **Determinism** — Math APIs take all entropy from callers. No
   `Random` / time / ambient state inside NTT or reduce.
3. **Public API surface** — Export only through `lib/pqlattice.dart`. Do not
   leak `src/` implementation types in the public barrel without review.
4. **Tests before claims** — Do not describe a routine as “correct NTT” in
   README until Path B gates in `AGENT_BRIEF` pass.
5. **Analyze and format** — `dart analyze` clean and `dart format` before
   considering a change done.

### 2.3 Security-adjacent (honest limits)

1. **No hard constant-time guarantee** on Dart VM / JS / Wasm. Prefer
   branch-light structure where it matters; never advertise platform CT.
2. **No secret lifetime guarantee** — Do not claim memory wipe. Callers use
   `zeroize` (or equivalent). Avoid logging coefficients of secret polys.
3. **No scheme logic** — Fujisaki–Okamoto, rejection sampling, HashToPoint,
   float FFT / Gaussian sampling, packing, and KATs stay **out**.
4. **Side-channel narrative** — Document intent (“branchless select in caller”)
   without promising observable timing invariance.

---

## 3. How to move through the codebase

### 3.1 Ownership map (where to edit)

| Change type | Primary location | Do not touch |
| ----------- | ---------------- | ------------ |
| Modulus / reduce / freeze | `lib/src/mod/` | NTT layer tables |
| Barrett / Montgomery params | `lib/src/mod/` | Scheme FO |
| Coefficient storage | `lib/src/poly/poly.dart` | Sampling |
| Vectors / matrices | `lib/src/poly/poly_vec.dart`, `poly_mat.dart` | KEM API |
| Schoolbook oracle | `lib/src/poly/ring_mul.dart` | Production hot path only via tests |
| Twiddles / NTT shape | `lib/src/ntt/ntt_params.dart`, `ntt_engine.dart` | Random zeta invention |
| Products in NTT domain | `lib/src/ntt/basemul.dart` | Wrong profile helper |
| SIMD | `lib/src/simd/` + parity tests | Default-on without AOT evidence |
| Kernel policy | `lib/src/api/` | Protocol code |
| Public exports | `lib/pqlattice.dart` | Ad-hoc exports from random files |
| Claims / mission rules | `doc/CLAIM_BOUNDARY.md`, `AGENTS.md` | Softening language without review |

### 3.2 Change workflow (mandatory)

```text
1. Identify the ring profile and domain (normal vs NTT).
2. Read the jurisdictional type’s library doc comment.
3. Write or extend a failing test that encodes the invariant.
4. Implement the minimal fix on the scalar path first.
5. Run: dart analyze && dart test
6. If SIMD touched: parity test scalar vs SIMD on fixed vectors.
7. Update doc/API.md or AGENT_BRIEF gates if surface or path status changed.
8. Re-read CLAIM_BOUNDARY before any README/pubspec wording change.
```

### 3.3 Navigation habits

- **Prefer reading call sites** (`pqcrypto` migration notes, tests) before
  renaming public symbols.
- **One concern per PR/commit** — e.g. “Barrett μ for 3329” separate from
  “FN-DSA zetas”.
- **Do not “while here”** refactor unrelated profiles.
- **Search before adding** — another helper for reduce almost certainly
  belongs next to `ModQ`, not a new top-level function.

---

## 4. Testing doctrine

1. **Property tests** over random coeffs in range beat only happy-path fixtures.
2. **Round-trip** — `inverse(forward(a)) ≡ a` (documented normalization).
3. **Linearity** — NTT of sum equals sum of NTTs (mod q).
4. **Mul agreement** — NTT-domain product vs `RingMul.schoolbookNegacyclic`
   after appropriate transforms.
5. **Bounds** — After public ops, coeffs satisfy the documented range.
6. **Fail-closed tests** — Montgomery not ready throws; `mlKemPairs` on wrong
   ring throws; dimension mismatch throws.
7. **No KAT substitution** — Full NIST algorithm KATs live in scheme packages.
   Intermediate-value vectors vs `pqcrypto` are welcome under `tool/` or `test/`
   with clear labels.
8. **Toy rings** — Small \(n, q\) tests for schoolbook/NTT structure are good;
   still add ML-KEM/FN-DSA-sized tests before claiming Path B done.

---

## 5. Performance rules

1. Optimize **after** scalar correctness.
2. Measure **AOT release** builds for any speed claim (`dart compile exe` /
   Flutter release)—not only JIT `dart run`.
3. **Acceleration is default** (`KernelMode.accelerated`). SIMD shape is used
   when capable and parity-proven; otherwise optimized scalar. Do not ship a
   “slow by default” path. Track upstream pairwise mul in
   [doc/SDK_SIMD_TRACKING.md](doc/SDK_SIMD_TRACKING.md)—do not invent `Int32x4 *`
   until the SDK provides it.
4. Do not depend on compiler **auto-vectorization**.
5. Prefer contiguous coeff layouts (`Int32List` internal) only with public API
   stability and tests.

---

## 6. Vulnerability and defect classes to actively avoid

| Class | Mitigation |
| ----- | ---------- |
| Wrong modulus arithmetic | Ring checks; tests with multiple presets |
| Off-by-one in basemul pairs | Fixture vectors; compare to reference intermediates |
| Using pointwise for ML-KEM | API split + tests that wrong helper rejects or fails oracle |
| Invented twiddles | Tables from cited specs/refs only; hash or length-check tables in tests |
| Intermediate overflow into undefined `int` behavior | Document max bound; reduce more often if needed |
| Silent identity NTT shipped as real | README/Path B status; tests that fail when zetas still empty if claiming completeness |
| Secret poly logging | Never `print` / log coeffs in library code |
| Timing overclaim | Claim boundary; no “constant-time NTT” marketing |
| Scope creep (FO, FFT float, CBD) | Reject PRs that add scheme files under `lib/src/` |
| Web breakage | Keep core free of FFI; run tests where CI allows on VM first |
| Dependency confusion | No unnecessary pub deps; pure Dart |

---

## 7. Documentation discipline

- Every new public type or method: **dartdoc** stating ring, domain, and
  failure modes.
- Status tags in comments: `TODO(Path B)`, `scaffold`, `deferred` — do not
  remove until gates pass.
- Changelog: user-visible API and correctness fixes under Keep a Changelog.
- Never soften `CLAIM_BOUNDARY.md` to make a marketing sentence easier.

---

## 8. Review checklist (before merge)

- [ ] Correct profile and basemul entry point
- [ ] Throws on ring/length mismatch
- [ ] Scalar path correct; SIMD parity if touched
- [ ] Tests added/updated for the invariant
- [ ] `dart analyze` clean; `dart test` green
- [ ] No forbidden claim wording
- [ ] No scheme/FO/float-FFT code in this package
- [ ] `doc/API.md` still accurate if surface changed
- [ ] Intermediate bounds documented if lazy reduction added

---

## 9. When unsure

1. Prefer **throwing** over guessing algebra.
2. Prefer **accelerated correct** over novel untested speedups; use reference only to verify.
3. Prefer **leaving a TODO(Path B)** over a plausible but untested formula.
4. Prefer **asking via test** (“does this match schoolbook?”) over matching
   only a blog pseudocode snippet.
5. Read `CONSUMER_API_AND_MIGRATION.md` before changing anything
   `pqcrypto` will call.

---

## 10. One-line standard

**Every coefficient path is ring-checked, domain-documented, scalar-verified,
and claim-honest—or it does not land.**
