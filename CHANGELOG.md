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

### Changed

- Minimum SDK constraint raised to `^3.13.0` (current stable line; see `doc/SDK_CONSTRAINTS.md`).
- Montgomery status updated from "deferred" to "ready, opt-in" across README, API.md, ARCHITECTURE.md (MontgomeryParams ready for 3329/12289/8380417; opt-in via `NttEngine(montgomeryParams:)`; not default).
- Benchmark suite added under `test/benchmarks/`: dependency-free harness with DSE-defeating sink, warm-up + 5 rounds + median, full context per row (SDK, OS, CPU, buildMode, profile, gitSha). Suites: ntt, basemul, reduce, pipeline, simd_parity, polyvec, schoolbook. Entry point `benchmarks_all.dart` emits TSV.
- BENCHMARKS.md §7: harness design rules, variation matrix, missing benchmarks (pqcrypto side-by-side, JIT vs AOT variance, memory profiling), honest limits; done benchmarks listed (Barrett vs `%`, PolyVec/PolyMat, schoolbook, Montgomery vs Barrett pipeline).

### Claim boundary

- Mathematical structure and profile tests — not a FIPS 140 module; full-scheme KATs remain in `pqcrypto`.
