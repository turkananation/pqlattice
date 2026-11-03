---
title: The mathematics, from A to Z
description: Ring profiles, reduce recipes, Montgomery domain, NTT structure, twiddle provenance and the exhaustive certifications behind every pqlattice coefficient.
keywords:
  - NTT mathematics
  - Montgomery reduction
  - Barrett reduction
  - post-quantum rings
---

Everything here is the exact math the library executes. Every constant cites
its spec, every reduce recipe names its bounds, and every claim links to an
executable test.

## The rings

| profile | q | n | shipped reduce recipe | signature constants |
| --- | --- | --- | --- | --- |
| ML-KEM | 3329 | 256 | Barrett μ/2²⁶ single-guard | v = 20159 = ⌈2²⁶/3329⌉ |
| ML-DSA | 8380417 | 256 | 32-bit-word Montgomery REDC, Montgomery-form twiddles, plain-domain | nPrime = −q⁻¹ mod 2³² = 4236238847, R² mod q = 2365951 |
| FN-DSA-512 | 12289 | 512 | k=27 single-guard Barrett | μ = 10921 = ⌊2²⁷/12289⌋, ψ = 49 |
| FN-DSA-1024 | 12289 | 1024 | k=27 single-guard Barrett | μ = 10921, ψ = 7 |

Provenance rule: twiddle tables come from cited specifications (FIPS 203 /
FIPS 204 shapes; Falcon-style negacyclic construction for FN-DSA where
ψⁿ ≡ −1, ψ²ⁿ ≡ 1 and ζₖ = ψ^bitrev(k)). Empty tables fail closed — the engine
throws rather than transform as identity. `tool/verify_constants.dart` re-checks
provenance every CI run.

## The transforms

Forward and inverse NTT over **Z_q**, the same Cooley–Tukey ladder the
reference implementations walk — the shipped paths change arithmetic, not
structure:

- per-layer butterflies with per-ring inlined reduce chains (see recipes);
- inverse walks conjugate twiddles (−ζ, mont form q − ζₘ) and ends with a
  **n⁻¹-mod-q** final scale folded into the same recipe;
- parities: linearity, round-trip inverse∘forward = id, mul-agreement vs
  schoolbook oracle (`RingMul.schoolbookNegacyclic`), toy-ring structural
  tests, and `*_Ref` oracle paths preserved verbatim.

### The three shipped reduce recipes

**Barrett single-guard (ML-KEM v = 20159, shift 26).**
For raw = ζ·x < 3329·3329: quot = (raw·20159) >> 26; t = raw − quot·q; one
conditional correction, `%` retained as an unreachable escape guard.
Certified exhaustively over all 3329² = 11,082,241 products.

**32-bit-word Montgomery REDC (ML-DSA).**
For prod = ζₘ·x with both in-range: m = ((prod mod 2³²)·nPrime) mod 2³²;
u = (prod + m·q) >> 32; one conditional subtraction. Bound: prod < q² < 2⁴⁶,
so prod + m·q < 2⁵⁶ — wrap-free in 64-bit ints, no division on the path.
Executable boundary evidence: `test/mldsa_wrap_boundary_test.dart`.

**k=27 single-guard Barrett (FN-DSA μ = 10921, shift 27).**
For raw = ζ·x: quot = (raw·10921) >> 27; r = raw − quot·q; two conditional
corrections + fix. Certified exhaustively over all 12289² =
151,019,521 products — every product that can ever occur in this modulus
family, `test/fndsa_exhaustive_residue_test.dart`.

## The Montgomery domain, in full

Represent a residue as **û = u·R mod q** for radix R = 2^w. In that
representation:

- multiplication is û·v̂ → REDC(û·v̂) where REDC(a) = (a·q̂·... ) exactly:
  m = (a mod R)·nPrime mod R with nPrime = −q⁻¹ mod R; u = (a + m·q)/R;
  drop one conditional; no division anywhere;
- `ModQ.toMont(x)` maps in (x·R²  step: reduce(x·R²) = xR), `ModQ.fromMont`
  maps out (one REDC), `ModQ.montMul(û, v̂)` composes products;
- forward transforms over Montgomery-form twiddles output Montgomery-domain
  NTT hats; the CHEAP math lives where chains of products amortize the
  representation.

Ready parameter profiles (fail-closed constructor otherwise): R = 2¹⁶ for
q = 3329 and q = 12289 (nPrime 3327 / 12287, R² 1353 / 10952); R = 2³² for
q = 8380417.

## Domains handed back by the API — the honest table

| surface | domain handed back |
| --- | --- |
| shipped `NttEngine` forward/inverse | plain residues [0, q) |
| `Basemul.mlKemPairs` / `pointwise` | NTT-domain, plain |
| opt-in mont engine forward (`montgomeryParams`) | NTT-domain **and Montgomery** |
| mont opt-in engine inverse | plain (converts on exit) |
| `Basemul.pointwiseMontgomery*` | NTT-domain and Montgomery |
| schoolbook `RingMul.schoolbookNegacyclic` | plain (algebraic oracle) |

Ring binding is structural: every call re-checks q and n and throws on
mismatch — never coerces, never guesses.

## What is deliberately out of scope

Scheme logic (Fujisaki–Okamoto, hashing-to-point), float-FFT and Gaussian
sampling, packing/serialization, KAT corpora, and any constant-time
advertising. This package executes the arithmetic layer; correctness gates
and interop discipline govern everything on top of it.
