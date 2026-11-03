---
title: Benchmarks and stage ledger
description: Every speed claim in pqlattice is a recorded measurement — the O1 acceleration record, the pqcrypto referee table, and the honest NO-GO ledger for fused and Montgomery candidates.
keywords:
  - pqlattice benchmarks
  - NTT benchmarks
  - Montgomery pointwise
  - post-quantum Dart performance
---

Every performance sentence in this project points at a recorded run. This page
is the current ledger: what shipped measured, what was evaluated and rejected,
and what remains parked with exact numbers attached.

<Info>
Discipline: every candidate must pass bit-identical parity against the shipped
engine before any timing counts, and end-to-end wins are only called wins at
pipeline level. Adoption bar: ≥10% end-to-end improvement (build at ≥15%).
</Info>

## The shipped stage (O1) — measured before merge

Per-ring inlined butterfly chains (Barrett for ML-KEM, 32-bit-word REDC with
Montgomery-form twiddles for ML-DSA, single-guard k=27 for FN-DSA). AOT
medians, run-to-run spread rstd ≤ 2.9%, 112/112 battery rows, all replaced
paths coefficient-identical to the previous engine:

| ring | full pipeline ns (before → after) | Δ |
| --- | --- | --- |
| ML-KEM (q=3329) | 172,862 → 142,595 | −17.5% |
| ML-DSA (q=8380417) | 332,935 → 158,107 | −52.5% |
| FN-DSA-512 (q=12289) | 629,486 → 388,409 | −38.3% |
| FN-DSA-1024 (q=12289) | 1,403,404 → 837,398 | −40.3% |

Certification: the ML-KEM Barrett recipe exhaustively over all 3329² products;
FN-DSA k=27 over all 12289² = 151,019,521 products
(`test/fndsa_exhaustive_residue_test.dart`). Docs rows (BENCHMARKS §6, §7.6,
API §4) ship with the behavior.

## The referee — pqcrypto vs pqlattice, one box, AOT medians

The permanent head-to-head harness lives in the pqcrypto repo
(`test/benchmarks/side_by_side.dart`, parity-first: identical inputs, aborts
unless coefficient-exact). Current measured posture:

| operation | pqcrypto | pqlattice | per-op gap |
| --- | --- | --- | --- |
| mlKem forward | 16,190 | 39,947 | ~2.5× |
| mlKem fwd+inverse | 39,198 | 88,475 | ~2.3× |
| mlKem baseMul pairs | 6,899 | 12,955 | ~1.9× |
| mlKem full pipeline | 77,797 | 152,238 | ~2.0× |
| mlDsa forward | 10,799 | 44,904 | ~4.2× |
| mlDsa fwd+inverse | 26,132 | 96,494 | ~3.7× |
| mlDsa pointwise | 1,417 | 11,164 | ~7.9× |
| mlDsa full pipeline | 54,282 | 165,165 | ~3.0× |

Honest reading: same algorithms, same NTT structure — the remaining gap
concentrates in the raw modular-arithmetic recipe (Montgomery-domain lazy
reduction) and in transform inlining.

## The rejection ledger — candidates measured and not built

### O2: fused two-layer butterflies (NO-GO all rings)

Each candidate passed parity-first, then time: forward projections
ML-KEM +17.4%, ML-DSA +38.2% — fused structure measured slower where inlining
had already paid the cost; FN-DSA fused was faster (−6.7% / −4.0% pipeline)
but short of the ≥10% adopt bar. Nothing beyond the shipped stage was built.

| ring | best pipeline projection | verdict |
| --- | --- | --- |
| ML-KEM | +15.7% (slower) | NO-GO |
| ML-DSA | +32.6% (slower); +28.0% with Montgomery pointwise | NO-GO |
| FN-DSA-512 | −6.7% (faster, under bar) | NO-GO |
| FN-DSA-1024 | −4.0% (faster, under bar) | NO-GO |

Sub-finding kept from that record: ML-DSA Montgomery two-REDC pointwise
measured 3,620 ns vs 10,875 ns shipped in-session (2.99×) — and the
**substrate** (MontgomeryParams, mont pointwise product APIs) is already in
the library, fail-closed.

### Montgomery pipeline through the public engine (NO-GO, per-op lead survives)

The full deferred-stage chain is wired and published as an opt-in
(`NttEngine(ring, montgomeryParams: ...)`, `Basemul.pointwiseMontgomery*`).
Measured end-to-end at HEAD (AOT, 24 rounds × 100 iters, parity-proven on two
patterns before timing — `test/benchmarks/ablation_mont.dart`):

| ring | montF vs shipped fwd | montI vs shipped inv | montPW vs shipped basemul | pipeline | verdict |
| --- | --- | --- | --- | --- | --- |
| ML-KEM | 1.82× slower | 1.78× slower | 1.29× slower | +83.2% | NO-GO |
| ML-DSA | 1.84× slower | 1.67× slower | **0.63× (1.58× faster)** | +71.3% | NO-GO |
| FN-DSA-512 | 1.67× slower | 1.34× slower | 0.75× faster | +52.8% | NO-GO |
| FN-DSA-1024 | 1.61× slower | 1.32× slower | 0.77× faster | +47.7% | NO-GO |

Anchor continuity: the O2 `redc2PW` arm re-measured 3,610 ns at HEAD vs 3,620
ns recorded at the O1 sha (Δ0.3%).

What the ledger says, precisely:

- The measurement hole was the *composition*, and it is now measured: the
  Montgomery pipeline through the generic engine call graph cannot beat the
  shipped inlined chains. Transform call-graph inlining is load-bearing.
- The ML-DSA (and FN-DSA) pointwise *mul* stays a measured per-op lead; its
  pipeline value exists only if the transform overhead is recovered by the
  same hand-inlining that paid off in O1, plus an in-domain public API doing
  the work today done by boundary conversions. That is a build project, and
  the honest envelope of its possible profit is bounded by these numbers.
- ML-KEM's Montgomery pairs product is measured slower per call (0.79× in
  this harness) because gammas convert on the fly per call — noted against
  any assumption that Montgomery is unconditionally faster.

## How these numbers are produced

- AOT rel-modes (`dart compile exe`), warmup rounds, medians of 24×100 timed
  iterations per arm (the pkg battery uses 5×1000 for the referee), spread
  reported as rstd%.
- Same-box pairing: candidate and shipped ship arms run in the same process
  so projections are within-session.
- Parity rows are printed before timing; any coefficient mismatch aborts
  before a single timing row is written.
- Harnesses live in `test/benchmarks/` and are never collected by `dart test`;
  they are run-evidence, not CI gates.
