# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-dev.1] - Unreleased

### Added

- Package scaffold: claim boundary, architecture, agent brief, **VM/compiler boundary**.
- Jurisdictional modules: mod (Barrett + Montgomery params), poly, PolyVec,
  schoolbook negacyclic oracle, NTT engines/tables (ML-KEM, ML-DSA, FN-DSA), basemul, SIMD shape.
- Acceleration **on by default** (`KernelMode.accelerated`).
- Unit tests: mod, Barrett profiles, NTT roundtrips, poly, ring mul, SIMD parity, kernels.
- Docs: TESTING, REDUCTION, ROADMAP, SECURITY_POSTURE, BENCHMARKS, TABLE_PROVENANCE,
  SDK_CONSTRAINTS, SDK_SIMD_TRACKING, CONTRIBUTING; MIT license.
- Correct ML-DSA Barrett recipe (`shift=48`) for full residue products.
- `NttParams.forRing`; NTT refuses missing tables (no identity no-op).
- Montgomery and table-provenance tests; `tool/verify_constants.py`.
- **Split-pass `Int32x4` NTT kernels** for ML-KEM, ML-DSA, FN-DSA-512, and
  FN-DSA-1024, forward and inverse: scalar multiply-reduce pass (the certified
  per-ring recipe) + 4-lane `Int32x4` add/sub combine with branchless
  canonicalization `d + ((d >> 31) & q)`. Bit-identical to the typed scalar
  kernels; `test/simd_ntt_parity_test.dart` is the merge gate.
- **Typed staged scalar NTT kernels** (`NttTyped`, `Int32List` lanes) used as
  the SIMD comparator and as the fallback on gated-off profiles/backends.
- `NttWorkspace`: 16-byte-aligned `Int32x4List` with an aliased `Int32List`
  scalar view over the same bytes.
- `LatticeKernels.preferSimdNtt(mode, ring, {required bool inverse})` and
  `LatticeKernels.simdNttEvidence(...)`: per-profile, per-direction evidence
  gate with a 1.5× AOT adoption threshold. `LatticeKernels.simdEnabled`
  reports the backend fact.
- `lib/src/ntt/ntt_reduce.dart`: shared, exhaustively-certified reduction
  recipes (`mlKemMulBarrett`, `mlDsaRedc`, `fnDsaReduceK27`) consumed by all
  three kernel tiers, so a rewrite cannot drift from the certified residues.

### Changed

- **SIMD backend gate rewritten**: `SimdCapability.supportsInt32x4` is now a
  measured backend decision — Dart VM **on**, dart2wasm **on** (`v128`, no
  speed claim; unmeasured locally), dart2js **off** (emulated `Int32x4`
  measured 2.7× slower than typed scalar). `PQLATTICE_SIMD_OFF` /
  `PQLATTICE_SIMD_FORCE` compile-time overrides replace the previous mutable
  scaffold flag.
- **`Basemul.pointwise` / `Basemul.mlKemPairs` inlined per ring**: ML-KEM
  Barrett, FN-DSA k=27, ML-DSA two-REDC (`REDC(REDC(a·b)·R²) = a·b`). Removes
  the `BarrettParams` object loads and the silent `%` fallback that
  `ModQ.reduceBarrett` hit on ML-DSA (documented `shift = 48` with
  `mu = 33587228` overflows 64-bit for full products).
- **`CoeffBuffer.fromList` clone fast path**: bulk typed-list copy when the
  source is already the destination width (~3.1 µs → ~0.15 µs at n = 256).
- `NttEngine` forward/inverse now stage through `_stagedForward` /
  `_stagedInverse` and dispatch on `(q, n)` plus the SIMD evidence gate; the
  former `List<int>` kernel bodies and their inlined reduce helpers were
  deleted.
- `LatticeKernels.preferSimd` is documented as a backend-level helper only;
  kernel dispatch must use `preferSimdNtt`.
- `test/benchmarks/simd_parity_benchmarks.dart` now benchmarks typed scalar vs
  split-pass `Int32x4` NTT per profile and direction (the deleted
  SIMD-pointwise benchmark is gone with the fake kernel).

- Provenance checker moved from Python to pure Dart: `tool/verify_constants.dart`
  (same checks, same output rows, same exit codes; `test.yml` runs
  `dart run tool/verify_constants.dart`; the former `tool/verify_constants.py`
  is retired).
- Minimum SDK constraint raised to `^3.13.0` (current stable line; see `doc/SDK_CONSTRAINTS.md`).
- Montgomery status updated from "deferred" to "ready, opt-in" across README, API.md, ARCHITECTURE.md (MontgomeryParams ready for 3329/12289/8380417; opt-in via `NttEngine(montgomeryParams:)`; not default).
- Benchmark suite added under `test/benchmarks/`: dependency-free harness with DSE-defeating sink, warm-up + 5 rounds + median, full context per row (SDK, OS, CPU, buildMode, profile, gitSha). Suites: ntt, basemul, reduce, pipeline, simd_parity, polyvec, schoolbook. Entry point `benchmarks_all.dart` emits TSV.
- BENCHMARKS.md §7: harness design rules, variation matrix, missing benchmarks (pqcrypto side-by-side, JIT vs AOT variance, memory profiling), honest limits; done benchmarks listed (Barrett vs `%`, PolyVec/PolyMat, schoolbook, Montgomery vs Barrett pipeline).

### Claim boundary

- Mathematical structure and profile tests — not a FIPS 140 module; full-scheme KATs remain in `pqcrypto`.
