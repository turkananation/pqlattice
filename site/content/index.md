---
title: Pure-Dart lattice arithmetic, evidence first
description: pqlattice is a pure-Dart NTT / modular-arithmetic engine for post-quantum schemes — accelerated by default, bit-exact by proof, and measured in the open.
keywords:
  - pqlattice
  - Dart cryptography
  - post-quantum
  - NTT acceleration
---

pqlattice is the arithmetic layer for post-quantum schemes written in Dart:
fast, deterministic ring/NTT/modular math with **acceleration on by default**
and correctness gates that outrank any speed number.

<Info>
The package executes the mathematical layer only — no scheme logic, no KAT
corpora, no float-FFT sampling. It exists so scheme packages (ML-KEM,
ML-DSA, FN-DSA) can adopt the algebra without rewriting it, byte-exact with
the reference implementations they already interoperate with.
</Info>

```dart
import 'package:pqlattice/pqlattice.dart';

final ring = RingParams.mlKem; // q=3329, n=256
final engine = NttEngine(ring); // accelerated by default
final f = engine.forward(poly);
final product = Basemul.mlKemPairs(aHat, bHat, ring);
```

## The shape

| layer | what it gives you |
| --- | --- |
| mod | `ModQ` reduce family: Barrett μ-chains, 32-bit REDC, Montgomery domain (`toMont`/`fromMont`/`montMul`) |
| ntt | `NttEngine` forward/inverse — per-ring inlined butterflies, opt-in Montgomery profile, `*_Ref` oracles preserved |
| products | `Basemul.mlKemPairs` (FIPS 203 pair profile), `pointwise`, Montgomery-domain variants |
| storage | contiguous typed coefficient lanes, ring-bound, hostile to silent coercion |

## Measured

0. The engine most recently improved end-to-end pipelines −17.5% (ML-KEM) to
   −52.5% (ML-DSA) by ring, certified coefficient-exact by exhaustive
   residue proofs over entire modulus squares. The rejection ledger records
   every candidate that lost, with numbers.
1. The live referee table against the pqcrypto package keeps the honest
   per-op posture measured (and it is not all wins — see the
   [measurements](measurements) page; measurement discipline outranks
   polish).

## Release posture

Formatting, static analysis, the full test suite, constant provenance and
the scriptable gates run on every change; docs ship in the same change as
the behavior they describe. Nothing is claimed but what a run recorded.
