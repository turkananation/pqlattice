# pqlattice Architecture

Last updated: 2026-10-27

## Package shape

```text
pqlattice/
  lib/
    pqlattice.dart
    src/
      api/
        kernel_mode.dart
        lattice_kernels.dart
      ring/
        ring_params.dart
      mod/
        mod_q.dart              # reduce, freeze, csubq, Barrett/Montgomery entry
        barrett_params.dart     # Barrett μ — default accel for q=3329
        montgomery_params.dart  # Montgomery domain — ready, opt-in via NttEngine
      poly/
        poly.dart
        poly_ops.dart
        poly_vec.dart
        poly_mat.dart
        ring_mul.dart           # schoolbook negacyclic oracle
      ntt/
        ntt_params.dart
        ntt_engine.dart         # + forwardVec/inverseVec; lazy-reduce intent
        basemul.dart
      simd/
        simd_capability.dart
        ntt_simd_int32x4.dart
  test/
  doc/
    CLAIM_BOUNDARY.md
    VM_COMPILER_BOUNDARY.md
    ARCHITECTURE.md
    AGENT_BRIEF.md
```

## Jurisdictional boundaries

| Module | Owns | Must not own |
| ------ | ---- | ------------ |
| `RingParams` | `q`, `n`, presets | NTT execution, sampling, KEM API |
| `ModQ` / `BarrettParams` / `MontgomeryParams` | Residue ops & reduction strategy params | Polynomial layout, twiddles |
| `Poly` / `PolyOps` | Storage, add/sub/neg | NTT, hashing, CBD |
| `PolyVec` / `PolyMat` | Vector/matrix storage | Full scheme matrix expand |
| `RingMul` | Schoolbook oracle | Hot-path NTT product |
| `NttParams` / `NttEngine` / `Basemul` | Transforms & NTT-domain products | Public KEM/signature API |
| `KernelMode` / SIMD | Which kernel runs | Protocol logic |

## Modular arithmetic posture

| Strategy | Status |
| -------- | ------ |
| `ModQ.reduce` (`%`) | Baseline, always correct |
| Barrett | **Default accelerated reduce** for ready profiles (`q=3329` ready); `%` is oracle only |
| Montgomery | **Deferred**; `MontgomeryParams.isReady == false`; `montMul` fails closed |
| Lazy reduction | Documented intent on NTT; implement with intermediate bounds |

See [VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md).

## Acceleration (default on)

**This package exists to accelerate lattice math.** See [ACCELERATION.md](ACCELERATION.md).

- Default kernel mode: `KernelMode.accelerated` (SIMD when capable, else optimized scalar).
- Barrett / structured NTT / basemul are first-class hot paths — not opt-in.
- `%` and schoolbook are **reference oracles** for tests.
- Hand-written SIMD is part of the acceleration stack when parity-proven; it is
  not compiler auto-vectorization. VM limits: [VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md).
- Interop constraint: [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md).

## Evidence posture

- **0.1.x scaffold:** unit properties, schoolbook oracle, strategy fail-closed tests
- **Later:** optional intermediate-value vectors vs `pqcrypto` / references — still not FIPS 140

## Out of scope

- Full ML-KEM / ML-DSA / SLH-DSA → `pqcrypto`
- Secret containers → `zeroize`
- AEAD / TLS → `pqforge` / `pqtransport`
- CBD / SHAKE sampling as product API → algorithm layer


## Consumer migration

See [CONSUMER_API_AND_MIGRATION.md](CONSUMER_API_AND_MIGRATION.md) for API shapes aimed at replacing `pqcrypto` internal poly/NTT, dual ML-KEM/ML-DSA rings, and FO placement (scheme layer only).


## FN-DSA integer profile

| Preset | q | n | Product helper |
| ------ | - | - | -------------- |
| `fnDsa512` | 12289 | 512 | `Basemul.pointwise` |
| `fnDsa1024` | 12289 | 1024 | `Basemul.pointwise` |

Floating-point FFT / sampler / NTRUSolve are **scheme-layer**, not this package.
Details: [FN_DSA_MATH.md](FN_DSA_MATH.md).

## Public API reference

See [API.md](API.md) for the consumer-facing surface (rings, ModQ, Poly, NTT, Basemul profiles).
