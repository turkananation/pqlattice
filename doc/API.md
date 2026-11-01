# pqlattice Public API

Last updated: 2026-10-27

Import:

```dart
import 'package:pqlattice/pqlattice.dart';
```

This is the **stable consumer contract** for scheme packages (`pqcrypto` and
future FN-DSA modules). Implementation status: many Path B items are scaffolds
(empty zetas, identity NTT, Barrett ready for q=3329, `mlKemPairs` unimplemented).
Semantics below are the **target API shape**; do not treat empty zetas as a
finished NTT.

Related: [ACCELERATION.md](ACCELERATION.md), [FIPS_ALIGNMENT.md](FIPS_ALIGNMENT.md), [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md), [ARCHITECTURE.md](ARCHITECTURE.md),
[CONSUMER_API_AND_MIGRATION.md](CONSUMER_API_AND_MIGRATION.md),
[FN_DSA_MATH.md](FN_DSA_MATH.md), [VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md).

---

## 1. Ring presets — `RingParams`

| Preset | \(q\) | \(n\) | Scheme target |
| ------ | ----- | ----- | ------------- |
| `RingParams.mlKem` | 3329 | 256 | FIPS 203 ML-KEM |
| `RingParams.mlDsa` | 8380417 | 256 | FIPS 204 ML-DSA |
| `RingParams.fnDsa512` | 12289 | 512 | FN-DSA-512 / Falcon |
| `RingParams.fnDsa1024` | 12289 | 1024 | FN-DSA-1024 / Falcon |

```dart
final ring = RingParams.mlKem;
ring.q; ring.n; ring.name;
ring.isFnDsaIntegerRing; // true only for fnDsa512/1024
```

Custom rings: `RingParams(q: ..., n: ..., name: ...)`.

**Does not** implement any full scheme.

---

## 2. Modular arithmetic — `ModQ`, `BarrettParams`, `MontgomeryParams`

| API | Role |
| --- | ---- |
| `ModQ.reduce(a, q)` | Reference reduce to \([0,q)\) |
| `ModQ.add` / `sub` / `mul` | Residues |
| `ModQ.freeze` / `csubq` / `center` | Scheme-facing helpers |
| `ModQ.reduceBarrett(a, BarrettParams)` | Barrett when `params.isReady`; else `%` |
| `BarrettParams.forQ(q)` / `BarrettParams.mlKem` | **Ready** for \(q=3329\) (\(\mu=5039\), shift 24); other \(q\) scaffold |
| `MontgomeryParams.forQ(q)` | **Ready** for \(q=3329\), \(q=12289\), \(q=8380417\); `isReady == true` |
| `ModQ.montMul` / `toMont` / `fromMont` | Montgomery domain ops; fail-closed for unknown moduli |

---

## 3. Polynomials — `Poly`, `PolyOps`, `PolyVec`, `PolyMat`, `RingMul`

| Type / API | Role |
| ---------- | ---- |
| `Poly.zero(ring)` / `Poly.fromCoeffs` / `clone` | Coefficient storage |
| `PolyOps` | Elementwise add/sub/neg (see source) |
| `PolyVec.zero` / `fromPolys` | Fixed-length vectors |
| `PolyMat.zero` / `at` / `setAt` | Row-major matrices; `mulVecNttPlaceholder` unimplemented |
| `RingMul.schoolbookNegacyclic(a, b, ring)` | **Working** correctness oracle |

---

## 4. NTT — `NttParams`, `NttEngine`

### Factories

| Factory | Ring |
| ------- | ---- |
| `NttParams.mlKem()` | ML-KEM |
| `NttParams.mlDsa()` | ML-DSA |
| `NttParams.fnDsa512()` | FN-DSA-512 |
| `NttParams.fnDsa1024()` | FN-DSA-1024 |

`zetas` are empty until Path B (engine is identity while empty).

### Engine

```dart
final ntt = NttEngine(
  RingParams.mlKem,
  params: NttParams.mlKem(),
  mode: KernelMode.auto, // scalar | simd | auto
);

Poly hat = ntt.forward(p);
Poly back = ntt.inverse(hat);
PolyVec hats = ntt.forwardVec(v);
```

- Scalar path is canonical.
- Optional SIMD must match scalar; see [VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md).
- Lazy reduction: implement with documented intermediate bounds (Path B).
- Accelerated default is monomorphic per ring: ML-KEM uses an inlined
  single-guard Barrett multiplier (v = 20159, shift = 26; pqcrypto-parity
  ceil-quotient form); ML-DSA uses inlined 32-bit-word Montgomery REDC
  butterflies with Montgomery-form twiddles precomputed at engine
  construction (plain-domain in, plain-domain out — zero conversions;
  fail-closed if Montgomery parameters are unavailable); FN-DSA uses inlined
  single-guard Barrett butterflies (mu = 10921, shift = 27) with a
  conjugate-twiddle inverse and a k=27 final scale. All hot loops are
  division-free with documented intermediate bounds: products < q^2 on
  ML-KEM/FN-DSA; the ML-DSA REDC u-term sum < 2^56.
- `KernelMode.reference` routes to the preserved reference paths verbatim
  (classic Barrett `_mul` chain) — oracle semantics unchanged.
- Constant provenance: `tool/verify_constants.py` checks the Barrett
  recipes, the Montgomery constants, and the FN-DSA zeta tables;
  reduction-boundary evidence lives in `test/mldsa_wrap_boundary_test.dart`
  (legacy k=48 wrap edge) and `test/fndsa_exhaustive_residue_test.dart`
  (exhaustive 12289^2 residue certification of the shipped k=27 chain).

---

## 5. NTT-domain products — `Basemul`

| Method | Use when |
| ------ | -------- |
| `Basemul.pointwise(aHat, bHat, ring)` | Complete-style NTT: **ML-DSA**, **FN-DSA** integer verify/mul |
| `Basemul.mlKemPairs(aHat, bHat, ring)` | **ML-KEM only** (incomplete NTT, degree-1 pairs). Scaffold throws until Path B |

Using `pointwise` for ML-KEM will **not** match FIPS 203 / `pqcrypto` intermediates.

---

## 6. Kernel policy — `KernelMode`, `LatticeKernels`

**Default is accelerated** ([ACCELERATION.md](ACCELERATION.md)).

```dart
enum KernelMode {
  accelerated,      // default — best available
  optimizedScalar,  // Barrett/NTT, no SIMD
  simd,
  reference,        // oracle / debug only
  auto,             // deprecated alias → accelerated
  scalar,           // deprecated alias → optimizedScalar
}

LatticeKernels.defaultMode; // KernelMode.accelerated
```

Do not rely on compiler auto-vectorization. Callers should not need a flag to
get the fast path.

---

## 7. What is **not** in this API

| Concern | Owner |
| ------- | ----- |
| Fujisaki–Okamoto / ML-KEM CCA | `pqcrypto` kem |
| ML-DSA rounding / hints / SampleInBall | `pqcrypto` |
| FN-DSA float FFT, Gaussian sampler, NTRUSolve | FN-DSA scheme package |
| CBD / SHAKE expand / ByteEncode | scheme layer |
| FIPS 140 / CMVP claims | none of these packages alone |

---

## 8. Quick profile cheat-sheet

```text
ML-KEM:  RingParams.mlKem  + NttParams.mlKem()  + Basemul.mlKemPairs
ML-DSA:  RingParams.mlDsa  + NttParams.mlDsa()  + Basemul.pointwise
FN-DSA:  RingParams.fnDsa* + NttParams.fnDsa*() + Basemul.pointwise
```

---

## 9. Versioning note

Breaking NTT domain conventions, zeta layout, or basemul formulas is a
**breaking** semver change. Scheme packages should pin `pqlattice` when they
cut over from in-tree math.
