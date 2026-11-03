---
title: Architecture and governance
description: Ownership map, change ritual, oracle discipline and the claim boundary that keeps pqlattice honest as it accelerates.
keywords:
  - pqlattice architecture
  - Change governance
---

pqlattice is small on purpose: a pure-Dart arithmetic core (no FFI, no
platform channels, no conditional imports that break web) with strict
jurisdiction over where things may change.

## Ownership map

| change type | primary location | do not touch |
| --- | --- | --- |
| modulus / reduce / freeze | `lib/src/mod/` | NTT layer tables |
| Barrett / Montgomery params | `lib/src/mod/` | scheme FO logic |
| coefficient storage | `lib/src/poly/` | sampling |
| schoolbook oracle | `lib/src/poly/ring_mul.dart` | hot path (tests only) |
| twiddles / NTT shape | `lib/src/ntt/ntt_params.dart`, `ntt_engine.dart` | invented constants |
| NTT-domain products | `lib/src/ntt/basemul.dart` | wrong-profile helpers |
| kernel policy | `lib/src/api/` | protocol code |
| public exports | `lib/pqlattice.dart` | ad-hoc barrel exports |
| measurement harnesses | `test/benchmarks/` | CI margins — run evidence |
| documentation site | `site/` (own package; `site/content` markdown) | root pubspec — never depend on site deps |

## Invariants worth knowing

1. ring binding: q and n checked on every call; mismatch throws.
2. profile-correct products: `mlKemPairs` for FIPS 203, `pointwise` for
   ML-DSA / FN-DSA integer — never substituted silently.
3. acceleration is the default (`KernelMode.accelerated`); `*_Ref` oracle
   bodies preserved verbatim for testing.
4. fail-closed: missing tables / unready Montgomery params throw; an empty
   zeta table never masquerades as a transform.
5. correctness beats performance — a slow-correct path may ship, a
   fast-wrong one may not.
6. claims follow runs: nothing in the docs asserts a property that a committed
   test or harness has not measured or proven.

## Change ritual

Identify the ring profile and domain → read the jurisdictional type's doc
comment → write the failing test that encodes the invariant → implement on
the scalar path first → `dart analyze` + `dart test` → SIMD parity if touched
→ update `doc/API.md` rows in the same change → re-read the claim boundary
before any wording changes.

## Where the deep details live

In-repo operator documentation: `doc/CLAIM_BOUNDARY.md` (what may be said),
`doc/REDUCTION.md` (lazy-reduction bounds), `doc/TABLE_PROVENANCE.md`
(twiddle citations), `doc/CONSUMER_API_AND_MIGRATION.md` (schemas embedding
these APIs), `doc/TESTING.md` (oracle hierarchy), and
`doc/BENCHMARKS.md` (the measurement record). This site is the readable
companion for the same facts.
