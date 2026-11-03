---
title: Roadmap and decision ledger
description: What shipped, what was measured and parked, and the documented keeper tasks for pqlattice's next accelerations and releases.
keywords:
  - pqlattice roadmap
  - post-quantum Dart ledger
---

The roadmap tracks in both directions on purpose — what shipped measured, and
what was measured and rejected:

## Shipped (measured, merged, certified)

- per-ring inlined butterfly chains as the accelerated default (O1 stage)
  with the certified proof-family: 3329² and 12289² exhaustive residue tests,
  ML-DSA REDC boundary documentation, ring table provenance gate (locked in
  via `tool/verify_constants.py` in CI), docs with behavior;
- a publishable docs/measurement site (this one), mirrored from repo doc/ truths;
- Montgomery substrate (parameters, mont pointwise products, opt-in engine
  profile): landed, fail-closed, measured — see ledger below.

## Measured, then parked (recorded with numbers)

- Fused two-layer butterflies: NO-GO all rings (fwd +17.4%/+38.2% slower on
  ML rings; FN −6.7%/−4.0% under the ≥10% bar).
- Montgomery pipeline through the public engine: NO-GO four rings
  (+83.2/+71.3/+52.8/+47.7%); the per-op mont pointwise lead survives on
  ML-DSA/FN-DSA (`0.63×/0.75×/0.77×`) — its value is conditional on
  recovering the transform-inlining gap and on an in-domain public API.
- ML-KEM mont pairs product: measured slower per call (on-the-fly gamma
  conversion) — parked against assumptions.

## Publish/keeper tasks

1. If `pqlattice` becomes public: the CI-grade parity option reopens on the
   pqcrypto side (git-ref dev dep or a dedicated bench workflow — one flip).
2. Re-baseline the referee table after each engine stage lands
   (`test/benchmarks/side_by_side.dart` in the consumer repo).
3. SDK SIMD tracking stays status-logged in `doc/SDK_SIMD_TRACKING.md`; no
   invented `Int32x4` math until the SDK provides the primitive itself.

## Explicit non-goals

Scheme logic of any kind inside this package (FO transforms, hashing-to-point,
float FFT, Gaussian sampling, packing, KATs). These are owned by the scheme
packages consuming pqlattice.
