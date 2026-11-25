# SIMD Acceleration in `pqlattice`

Last updated: 2026-11-13

Acceleration is **on by default** (`KernelMode.accelerated`). This document
describes the shipped `Int32x4` NTT layer, the backend and evidence gates, the
measured results, and the wording that the measurements do and do not support.

Related: [ACCELERATION.md](ACCELERATION.md), [SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md),
[SDK_CONSTRAINTS.md](SDK_CONSTRAINTS.md), [BENCHMARKS.md](BENCHMARKS.md),
[VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md), [REDUCTION.md](REDUCTION.md).

---

## 1. Shape of the kernel

The shipped kernel is a **two-pass stage**, not a fully vectorized butterfly:

1. **Scalar multiply-reduce pass.** For the stage, every high-half coefficient
   is multiplied by the stage twiddle and reduced with the profile's certified
   recipe (`mlKemMulBarrett`, `mlDsaRedc`, `fnDsaReduceK27` in
   `lib/src/ntt/ntt_reduce.dart`).
2. **`Int32x4` combine pass.** Add/sub, then branchless canonicalization
   `d + ((d >> 31) & q)` over 4 lanes.

Why this split:

- Dart has `Int32x4` `+`, `-`, `>>`, `&`, but **no lane-wise `operator *` on a
  stable SDK**, and 32-bit wrap would not carry ML-DSA's `q² ≈ 2^46` even if it
  existed. The multiply half must stay scalar for exact residues.
- The add/sub half is the part that maps cleanly to 4 lanes, and it is
  bit-exact by construction: for inputs in `[0, q)` the intermediates satisfy
  `lo + hi ∈ [0, 2q)` and `lo - hi ∈ (-q, q)`, so one branchless conditional
  correction equals the scalar `?:` form exactly. No new algebra is introduced.
- Only stages with `len >= 4` have whole 16-byte groups, so `len ∈ {1, 2}` stays
  scalar. Every `start` is a multiple of `2·len >= 8`, so the byte offset of a
  block is 16-byte aligned.

Twiddle indexing is **per block within a stage**, not per stage. Hoisting
`zetas[k++]` out of the block loop is a correctness bug (this was caught by the
parity gate during development and is documented on the kernel).

Files:

| File | Role |
| ---- | ---- |
| `lib/src/ntt/ntt_reduce.dart` | Certified reduction recipes shared by every kernel tier |
| `lib/src/ntt/ntt_scalar.dart` | Scalar kernels on `Int32List` lanes (comparator + fallback) |
| `lib/src/simd/ntt_workspace.dart` | 16-byte-aligned `Int32x4List` + aliased `Int32List` |
| `lib/src/simd/ntt_simd_int32x4.dart` | Six split-pass kernels + three combine helpers |
| `lib/src/simd/simd_capability.dart` | Backend gate (`Int32x4` worthwhile or not) |
| `lib/src/api/lattice_kernels.dart` | Per-profile, per-direction evidence gate |
| `lib/src/ntt/ntt_engine.dart` | Staging, typed copy fast paths, dispatch |

---

## 2. Staging is part of the design

`NttEngine` never runs an NTT loop directly on `Poly.coeffs`. It copies into
`NttWorkspace` lanes, runs the kernel, and copies back. Both copies have typed
fast paths (`is Int16List` / `is Int32List`) so the copy is a direct typed load
or store rather than an interface access.

This is measured, not stylistic: running the scalar loop directly on an
interface-typed `List<int>` parameter measured ~3× slower at engine level. The
same effect is why `NttScalar` takes `Int32List`, not `List<int>`.

Copies are value-exact, so staging cannot change residues. Results are
bit-identical to running the loop in place.

---

## 3. Gates

### 3.1 Backend gate — `SimdCapability`

`Int32x4` is always *available*; it is not always *profitable*. Decided once per
isolate:

| Backend | Lowering | Decision |
| ------- | -------- | -------- |
| Dart VM (AOT/JIT) | real vector registers | **on** |
| dart2wasm | `v128` | **on**, no speed claim (unmeasured locally) |
| dart2js | emulated on JS numbers | **off** — measured **0.50×** (2× slower) |

`identical(0, 0.0)` is the dart2js discriminator (true only there; false on the
VM and on dart2wasm). Overrides:

| Flag | Effect |
| ---- | ------ |
| `-DPQLATTICE_SIMD_OFF=true` | Disables `Int32x4` on every backend (wins over force) |
| `-DPQLATTICE_SIMD_FORCE=true` | Enables it regardless of the backend default |

### 3.2 Evidence gate — `LatticeKernels.preferSimdNtt`

`KernelMode.accelerated` uses the vector kernel only where a measured AOT run
cleared the **1.5× adoption threshold**. The comparison is taken at **engine
level** (`forwardInPlace` / `inverseInPlace`, staging included) because that is
what callers execute. `simdNttEvidence(ring, inverse: ...)` holds the table.

| Mode | Vector kernel |
| ---- | ------------- |
| `accelerated` | Only where the evidence table says ≥ 1.5× |
| `simd` | Forced when the backend supports `Int32x4` (parity-proven, not necessarily faster) |
| `optimizedScalar` | Never |
| `reference` | Never |

---

## 4. Measured results

Host: linux x64, 4 CPUs, Dart 3.14.0 stable, AOT (`dart compile exe`), medians
of 5–7 rounds × 1000 iterations with warm-up. Run-to-run spread on this box is
6–19% for cross-package rows; treat differences below ~10% as unresolved.

### 4.1 Engine-level NTT (the gate metric)

`KernelMode.accelerated` (vector kernel) vs `optimizedScalar` (scalar kernel),
three alternating trials each; range shown.

| Profile | Forward | Inverse |
| ------- | ------- | ------- |
| ML-KEM (q=3329, n=256) | **2.31× / 2.30× / 2.31×** | **2.05× / 2.03× / 2.05×** |
| ML-DSA (q=8380417, n=256) | **2.12× / 2.12× / 2.12×** | **1.87× / 1.91× / 1.89×** |
| FN-DSA-512 (q=12289) | **1.51× / 1.52× / 1.53×** | **1.51× / 1.51× / 1.53×** |
| FN-DSA-1024 (q=12289) | **1.57× / 1.58× / 1.57×** | **1.57× / 1.58× / 1.57×** |

All four shipped profiles clear 1.5× in both directions, so all four use the
vector kernel under `accelerated`.

### 4.2 Kernel-only (the math-layer marginal win)

`NttSimdInt32x4` vs `NttScalar` on identical staged lanes (suite `simd`,
`test/benchmarks/simd_parity_benchmarks.dart`):

| Profile | Forward | Inverse |
| ------- | ------- | ------- |
| ML-KEM | 1.04×–1.11× | 1.16×–1.20× |
| ML-DSA | 1.09×–1.29× | 1.09× |
| FN-DSA-512 | 1.81×–1.88× | 1.59×–1.65× |
| FN-DSA-1024 | 1.67×–1.73× | 1.70×–1.74× |

The n=256 rings show a smaller **kernel-only** margin because the split combine
pass adds a traversal and the scalar add/sub butterfly is already cheap. The
engine-level win is larger because staging plus the scalar kernel interact
badly in the AOT-compiled call path (§2), while the vector kernel does not.

Both tables are reported; neither is quoted without its basis.

### 4.3 Against `pqcrypto` (official referee)

`pqcrypto` branch `bench/ntt-side-by-side`, `test/benchmarks/side_by_side.dart`,
same host, same AOT flags, identical deterministic inputs, **bit-identity
asserted coefficient-wise before timing** (ML-KEM 50/50 trials, ML-DSA 25/25).
A single recorded run, AOT medians:

| Operation | `pqcrypto` ns | `pqlattice` ns | Ratio |
| --------- | ------------: | -------------: | ----: |
| mlKem forward | 20,819 | 8,905 | pqlattice **2.34× faster** |
| mlKem forward+inverse | 41,358 | 20,082 | **2.06× faster** |
| mlKem pairs basemul | 6,481 | 7,735 | pqlattice 1.19× slower |
| mlKem full pipeline | 76,259 | 37,150 | **2.05× faster** |
| mlDsa forward | 11,558 | 9,782 | **1.18× faster** |
| mlDsa forward+inverse | 22,603 | 21,311 | **1.06× faster** |
| mlDsa pointwise | 1,443 | 5,196 | pqlattice 3.60× slower |
| mlDsa full pipeline | 55,797 | 36,364 | **1.53× faster** |

Honest reading: the transform and pipeline rows favour `pqlattice`; ML-KEM
pair basemul and ML-DSA pointwise remain slower than `pqcrypto`. The ML-DSA
pointwise gap is the price of exact plain-domain residues through two 32-bit
REDCs; `pqcrypto` keeps lazy Montgomery-domain representatives. Do not quote
the pipeline ratio as a per-operation claim.

### 4.4 Web backends

- **dart2js:** 0.50× — 2× slower than typed scalar. Disabled in
  `SimdCapability`.
- **dart2wasm:** enabled, **unmeasured**. Local Node 20 cannot compile the
  module (`CompileError: unknown type form`), so no web-SIMD speed claim is
  made in either direction.

---

## 5. Interop / FIPS invariant

Acceleration must not change observable residues relative to the reference
path for the same operation on the same inputs. Evidence:

- `test/simd_ntt_parity_test.dart` — kernel-level bit-exactness for all four
  profiles, both directions, 25 random polys each, seven adversarial patterns
  (zeros, ones, `q-1`, alternating extremes, ramps, `q>>1`), plus engine-level
  `reference` / `optimizedScalar` / `accelerated` / `simd` agreement and
  round-trip.
- `test/fndsa_exhaustive_residue_test.dart` — all 12289² products through the
  shipped k=27 chain.
- `test/barrett_mlkem_test.dart` — all 3329² products through the ML-KEM chain.

If a vector path cannot guarantee parity, it is not enabled under
`accelerated`. This preserves `doc/INTEROP_AND_FIPS_RULE.md`.

---

## 6. Adding or extending a SIMD kernel

1. Implement under `lib/src/simd/` with an explicit scalar fallback.
2. Reuse `ntt_reduce.dart`; do not write a second copy of a reduction.
3. Gate on `SimdCapability` **and** an evidence entry, never on availability
   alone.
4. Add bit-exact parity tests for every profile and direction you claim.
5. Measure AOT at engine level; add a row here with the basis stated.
6. Update `ACCELERATION.md` and `CHANGELOG.md`.
7. Never change public residue contracts or claim FIPS module status.

---

## 7. Claims

**Allowed**

- “Split-pass `Int32x4` NTT kernels: scalar multiply-reduce plus a 4-lane
  butterfly combine, bit-identical residues.”
- “SIMD-assisted NTT on the Dart VM, with a measured 1.5×–2.3× engine-level
  speedup over the scalar path, per profile.”
- “`pqlattice` pipelines measured faster than `pqcrypto` on the same host in
  the official referee (ML-KEM ~2.05×, ML-DSA ~1.53× in the recorded run).”
- “dart2js is gated off because emulated `Int32x4` measured slower.”

**Forbidden**

- “Full SIMD NTT”, “fully vectorized butterfly”, “SIMD basemul”
- “AVX2”, “AVX-512”, “auto-vectorized by the VM”
- “Constant-time SIMD”, “FIPS-validated SIMD module”
- Any web/wasm SIMD speedup claim (unmeasured)
- Quoting the pipeline ratio as a per-operation or universal claim

Compiler limits that bound future work are in
[VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md); upstream SDK tracking is in
[SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md).
