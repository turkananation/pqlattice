---
title: Getting Started
description: Install pqlattice, run your first ring NTT and basemul, and learn the failure modes the engine guarantees.
keywords:
  - pqlattice getting started
  - Dart NTT example
---

Install:

```yaml
dependencies:
  pqlattice: ^0.1.0-dev.1
```

## First transform and product

```dart
import 'package:pqlattice/pqlattice.dart';

void main() {
  // Ring binding is checked on every call: mismatch throws, never coerces.
  final ring = RingParams.mlKem; // q=3329, n=256
  final engine = NttEngine(ring); // KernelMode.accelerated is the default

  final h = engine.forward(a);
  final product = Basemul.mlKemPairs(aHat, bHat, ring);
}
```

Four shipped profiles: ML-KEM (q=3329, n=256), ML-DSA (q=8380417, n=256),
FN-DSA-512 and FN-DSA-1024 (q=12289). Every forward/inverse is deterministic,
allocation-free in place, and bit-identical to the preserved `*_Ref` oracle
paths in the same class.

## Opt-in Montgomery domain

The deferred-stage substrate is public and fail-closed:

```dart
final mont = NttEngine(
  ring,
  montgomeryParams: MontgomeryParams.forQ(ring.q), // throws if not ready
);
final hatMont = mont.forward(poly); // NTT-domain AND Montgomery-domain
// observe in the normal domain explicitly: ModQ.fromMont(...)
```

Pair with the Montgomery-domain pointwise product APIs when you want them.
The [measurements](measurements) ledger reports what this opt-in currently
buys (and what it costs) per ring — the engine stays opt-in until a measured
case clears the adopt bar.

## Failure modes you can rely on

- tables missing → throw (never a silent identity transform);
- Montgomery profile not ready → throw;
- ring/profile mismatch (e.g. `pointwise` vs `mlKemPairs` on the wrong ring)
  → throw;
- math APIs take all entropy from callers; no ambient randomness.

## If you are projecting a scheme on top of this

Read `doc/CONSUMER_API_AND_MIGRATION.md` before designing against the engine:
domain honesty per call is the contract scheme packages should rely on, and
the FN-DSA/ML-DSA basemul profiles are deliberate (`mlKemPairs` for FIPS 203,
`pointwise` for ML-DSA/FN-DSA integer products).
