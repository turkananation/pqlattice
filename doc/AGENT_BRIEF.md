**Read [AGENTS.md](../AGENTS.md) first** — mission-critical invariants and workflow.

# Agent Brief: Bootstrap & Implement `pqlattice`

This file is the working contract for a **local agent** (or human) continuing
from the scaffold. Follow package conventions from `pqcrypto` and the claim
boundary in `doc/CLAIM_BOUNDARY.md`.

## Objective

Deliver a **correct, pure-Dart lattice math library** with:

1. Clear jurisdictional APIs (one primary type per responsibility).
2. Scalar NTT / iNTT / basemul for at least the ML-KEM-style ring
   (\(q = 3329\), \(n = 256\), incomplete NTT as used in FIPS 203).
3. Optional SIMD kernel hooks (`KernelMode`) that default safely to scalar.
4. Unit tests that prove mathematical properties (not full NIST KATs).
5. README + claim boundary that never overclaim FIPS 140 or full algorithms.

## Non-goals (do not implement in this package)

- Full ML-KEM encaps/decaps or ML-DSA sign/verify.
- Checking in 3000 ML-KEM KATs (belongs in `pqcrypto`).
- FFI / assembly / platform channels.
- Guaranteeing constant-time execution on JS/Wasm/JIT.

## Success paths

### Path A — Scaffold green (minimum for PR #1)

| Gate | Command / check |
| ---- | ---------------- |
| Analyze clean | `dart analyze` → no issues |
| Format | `dart format --set-exit-if-changed .` |
| Tests run | `dart test` → all pass (even if mostly structural) |
| Public export | `package:pqlattice/pqlattice.dart` exports only intended API |
| Claims | README and `doc/CLAIM_BOUNDARY.md` agree; no forbidden wording |

### Path B — Scalar math correctness

| Gate | Evidence |
| ---- | -------- |
| Reduction | Random \(a \in [0, q^2)\): `ModQ.reduce(a)` in \([0, q)\) |
| NTT round-trip | For random poly with coeffs in \([0, q)\):  
  `inverse(forward(a)) ≡ a` (mod \(q\)), allowing documented normalization |
| Linearity | `forward(a+b) ≡ forward(a)+forward(b)` |
| Basemul | Small fixed vectors vs schoolbook product in the ring |
| No BigInt in hot path | Coefficients stay in `int` / typed data |

### Path C — Optional SIMD

| Gate | Evidence |
| ---- | -------- |
| Parity | SIMD path and scalar path identical outputs on random inputs |
| Fallback | With `KernelMode.scalar`, SIMD code never required |
| No public SIMD types | Examples and public API use `Poly`, not `Int32x4` |
| Honest docs | README states AOT/JIT variance; no “always faster” claim |

### Path D — Integration readiness

| Gate | Evidence |
| ---- | -------- |
| `pqcrypto` can depend | Stable `RingParams` / `NttEngine` without importing KEM types |
| Zeroize-friendly | Polys expose coefficient buffers that callers can zero |
| Version | Semver `0.1.0-dev.x` until Path B is solid; `0.1.0` when Path B gates pass |

## Implementation order (recommended)

1. `RingParams` + `ModQ` + tests.
2. `Poly` / `PolyOps` + tests.
3. `NttParams` (zetas) + scalar `NttEngine` + round-trip tests.
4. `Basemul` + product tests.
5. `KernelMode` + stub SIMD module that delegates to scalar.
6. Real `Int32x4` kernels only after scalar is green; parity tests mandatory.
7. Example + dartdoc on public types.

## API design rules

- Prefer **static methods or small immutable facades** over deep inheritance.
- Public library file re-exports only; implementation under `lib/src/`.
- Name presets explicitly: e.g. `RingParams.mlKem` — not “default crypto”.
- Errors: prefer `ArgumentError` / `StateError` for programmer mistakes; do not
  throw on “verification failure” patterns that belong to higher layers.

## Claim checklist before every commit message / README edit

- [ ] No “FIPS validated” / “CMVP” / “certified”
- [ ] No “implements ML-KEM/ML-DSA” as a full algorithm
- [ ] SIMD described as optional / best-effort
- [ ] Evidence described as unit properties unless KAT-style vectors exist

## Reference packages

- Conventions, badges, claim tone: `pqcrypto`
- Secret lifetime (dependency later if needed): `zeroize`
- Do not copy KEM/DSA modules into this repo

## Done definition for the agent

The agent is done with the **bootstrap phase** when Path A is green and
`doc/AGENT_BRIEF.md` still matches the tree. The agent is done with the
**math MVP** when Path B is green. Path C is optional stretch; Path D is for
the first consumer integration.

---

## Modular strategy (Path B detail)

1. Keep `ModQ.reduce` as the reference oracle.
2. Implement real `BarrettParams.forQ(3329)` (\(\mu\), shift, `maxInputAbs`) and
   `ModQ.reduceBarrett`; property-test against `reduce`.
3. Do **not** implement Montgomery until Barrett + scalar NTT pass Path B gates
   unless there is a measured need. Leave fail-closed stubs.
4. Document lazy-reduction max intermediates in `NttEngine` comments or a short
   `doc/NTT_BOUNDS.md` when butterflies land.
5. Never rely on compiler auto-vectorization (see `VM_COMPILER_BOUNDARY.md`).

## Poly surface (Path B)

- Use `RingMul.schoolbookNegacyclic` as oracle for NTT mul on random polys.
- Prefer `PolyVec` in APIs that would otherwise pass `List<Poly>`.
- Coeff storage: `List<int>` is fine for scaffold; consider `Int32List` internally
  when adding SIMD (keep public API stable).

## Docs gate

Before transfer sign-off, these must exist and agree:

- [ ] `doc/CLAIM_BOUNDARY.md`
- [ ] `doc/VM_COMPILER_BOUNDARY.md`
- [ ] `doc/ARCHITECTURE.md`
- [ ] `doc/AGENT_BRIEF.md`


## Consumer / pqcrypto replacement

Read `doc/CONSUMER_API_AND_MIGRATION.md` before designing basemul APIs. ML-KEM needs **pair basemul**, not only pointwise. FO is never implemented here.


## FN-DSA path (parallel to ML-KEM)

- Presets: `RingParams.fnDsa512` / `fnDsa1024`, matching `NttParams`.
- Use **pointwise** basemul after complete-style NTT — never `mlKemPairs`.
- Path B: zeta tables mod 12289; NTT round-trip; schoolbook oracle on small n first.
- Do **not** implement complex FFT, Gaussian sampling, or NTRUSolve here.
- Doc: `doc/FN_DSA_MATH.md`.

## API reference

Keep implementations aligned with [API.md](API.md). Profile cheat-sheet: ML-KEM → `mlKemPairs`; ML-DSA/FN-DSA → `pointwise`.


## Barrett (partial Path B)

- `BarrettParams.mlKem` / `forQ(3329)` is **ready** (\(\mu=5039\), shift 24).
- Property tests: `test/barrett_mlkem_test.dart` vs `ModQ.reduce`.
- Still TODO: Barrett for \(q=12289\) and \(q=8380417\); full NTT zetas.


## Interop gate

Before any claim that `pqcrypto` can default to `pqlattice`:

1. Parity with current pqcrypto ML-KEM (and ML-DSA when ported) math.
2. pqcrypto KATs green.
3. pqcrypto interop vs **OpenSSL, BoringSSL, liboqs, AWS-LC** still byte-exact.

See [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md).

## Efficiency (landed)

- Fused Barrett on ML-KEM/ML-DSA NTT + basemul; addFast/subFast
- In-place NTT / basemul APIs
- ML-DSA NTT tables + round-trip tests
- SIMD-shaped pointwise helper; SimdCapability still gates default dispatch
- tool/bench/ntt_bench.dart

