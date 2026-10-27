# SIMD Acceleration in `pqlattice`

Last updated: 2026-10-27

Acceleration is **on by default** (`KernelMode.accelerated`). This document
describes the SIMD layer, capability gating, how to force or disable it, and
the Dart VM reality that bounds what is possible without compiler work.

---

## 1. Design goals

| Goal | Policy |
|------|--------|
| Speed first | Default path is accelerated (SIMD when safe and measured, else optimized scalar). |
| Interop never broken | Residues after every public operation stay in the same canonical range as Barrett/scalar (byte-exact interop with OpenSSL / BoringSSL / liboqs / AWS-LC style KATs). |
| Web-safe | No `dart:ffi`. Only pure Dart + `dart:typed_data` (`Int32x4`, `Float32x4`, packed `Int16List` / `Int32List`). |
| Fail closed on capability | If SIMD is not available or not parity-proven for a profile, fall back to optimized scalar (still accelerated relative to naive `%` loops). |

---

## 2. What “SIMD” means on the Dart VM

- Dart exposes **fixed-width** SIMD types: `Int32x4`, `Float32x4` (and some
  related views). There is **no** `Int16x8` or pairwise integer multiply on
  `Int32x4` in the public API.
- The VM does **not** auto-vectorize ordinary `for` loops over `List` or
  `Int16List` the way a C compiler with `-O3 -march=native` often does.
- AOT and JIT differ in intrinsification; hand-shaped 4-wide loops with
  explicit `Int32x4` load/store improve the odds that the backend maps them
  to SIMD registers, but **element-wise multiply and Barrett reduction still
  run as scalar `int` ops** inside the 4-wide block today.
- Therefore the current SIMD kernel is **shape + memory layout + explicit
  4-wide structure**, not a full AVX2-style integer butterfly. Full butterfly
  SIMD for NTT requires either:
  - future VM intrinsics / better auto-vectorization, or
  - platform-specific code (out of scope for pure-Dart web-safe package).

See `doc/VM_COMPILER_BOUNDARY.md` for the factual compiler limits.

**Upstream tracking:** Dart SDK issues that can remove the pairwise-mul gap
(and related SIMD surface) are registered in
[`doc/SDK_SIMD_TRACKING.md`](SDK_SIMD_TRACKING.md). Review that file on the
documented cadence before changing SIMD kernels or claims.

---

## 3. Public control surface

```dart
import 'package:pqlattice/pqlattice.dart';

// Default — acceleration on (SIMD if capable + parity, else optimized scalar)
final ntt = NttEngine(RingParams.fnDsa512); // mode: KernelMode.accelerated

// Force SIMD-shaped kernels when available
final nttSimd = NttEngine(
  RingParams.fnDsa512,
  params: NttParams.fnDsa512(),
  mode: KernelMode.simd,
);

// Optimized scalar only (still Barrett, fused reduce, packed storage)
final nttScalar = NttEngine(
  RingParams.mlKem,
  mode: KernelMode.optimizedScalar,
);

// Reference / oracle (simple `%`, for tests and KATs)
final nttRef = NttEngine(
  RingParams.mlKem,
  mode: KernelMode.reference,
);
```

### How to “flip” SIMD

| Intent | Setting |
|--------|---------|
| Production default | `KernelMode.accelerated` (or omit; this is the constructor default) |
| Prefer SIMD shape aggressively | `KernelMode.simd` |
| Disable SIMD, keep fast scalar | `KernelMode.optimizedScalar` |
| Debug / oracle only | `KernelMode.reference` |

Deprecated aliases: `KernelMode.auto` → accelerated; `KernelMode.scalar` → optimizedScalar.

Runtime capability is reported by `SimdCapability` (see
`lib/src/simd/simd_capability.dart`). Under `accelerated`, the engine may
consult capability before selecting the SIMD pointwise helper; under `simd`
it prefers the SIMD shape when the types are available.

---

## 4. Where SIMD is applied today

| Kernel | Status | Notes |
|--------|--------|-------|
| Pointwise product (complete NTT domain) | `NttSimdInt32x4.pointwiseInPlace` | 4-wide load/store + scalar mul + Barrett; parity-tested |
| NTT / iNTT butterflies | Optimized scalar (fused Barrett, `addFast`/`subFast`) | Full SIMD butterflies deferred until VM support or measured AOT win |
| ML-KEM pair basemul | Optimized scalar fused | Same residue policy |
| Coefficient storage | Packed `Int16List` / `Int32List` via `CoeffBuffer` | Cache-friendly for both scalar and SIMD-shaped loops |

FN-DSA integer NTT (q=12289, n=512/1024) uses the same accelerated scalar
path and packed storage; pointwise product can use the SIMD helper when
selected.

---

## 5. Interop / FIPS invariant under acceleration

Acceleration **must not** change observable residues relative to the
reference path for the same mathematical operation on the same inputs
(within the documented reduction range). Tests:

- `simd_pointwise_parity_test.dart` — SIMD vs scalar pointwise
- Profile NTT roundtrips and Barrett tests for ML-KEM / ML-DSA / FN-DSA

If a SIMD path cannot guarantee parity, it is not enabled under
`accelerated` until fixed. This preserves the binding constraint in
`doc/INTEROP_AND_FIPS_RULE.md`.

---

## 6. Adding or extending a SIMD kernel

1. Implement under `lib/src/simd/` with a clear scalar fallback.
2. Gate on `SimdCapability` and/or `KernelMode`.
3. Add a **parity test** against the optimized scalar / reference path for
   every profile (ML-KEM, ML-DSA, FN-DSA) you claim.
4. Document in this file and in `ACCELERATION.md`.
5. Never change public residue contracts or claim FIPS module status.

---

## 7. Claims (honest)

- Allowed: “SIMD-shaped kernels with packed storage; acceleration default;
  pure Dart; interop-preserving residues.”
- Forbidden: “uses AVX2/AVX-512”, “auto-vectorized by the VM”, “constant-time
  SIMD”, “FIPS-validated SIMD module”.

Compiler/VM improvements that would make lattice math “super fast” by
default are listed in `VM_COMPILER_BOUNDARY.md` (intrinsics for modular
mul/reduce, better AOT vectorization of tight int loops, optional
profile-guided NTT templates).
