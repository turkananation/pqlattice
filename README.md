# pqlattice

Pure-Dart **lattice and polynomial arithmetic** for post-quantum cryptography:
modular reduction, polynomials over ℤ𝑞 [ 𝑋 ] / ( 𝑋256 +1)  NTT / inverse NTT,
NTT-domain products, with **acceleration on by default** (Barrett, optimized NTT/basemul, SIMD when capable).

## Project signals

[![Dart SDK](https://img.shields.io/badge/Dart-%5E3.13.0-0175c2?style=for-the-badge&logo=dart&logoColor=white)](pubspec.yaml)
[![license](https://img.shields.io/badge/license-MIT-2ea043?style=for-the-badge)](LICENSE)
[![runtime](https://img.shields.io/badge/runtime-pure%20Dart%20%7C%20optional%20SIMD-0175c2?style=for-the-badge&logo=dart&logoColor=white)](pubspec.yaml)
[![claim boundary](https://img.shields.io/badge/CMVP%20%2F%20FIPS%20140-not%20validated-bf8700?style=for-the-badge)](doc/CLAIM_BOUNDARY.md)

**Math layer only.** This package does **not** implement full ML-KEM, ML-DSA, or
FN-DSA; does **not** claim FIPS 140 / CMVP validation; and does **not** guarantee
hard constant-time or hard secure-erasure on the Dart VM, dart2js, or dart2wasm.

| Read first | Purpose |
| ---------- | ------- |
| [INTEROP_AND_FIPS_RULE.md](doc/INTEROP_AND_FIPS_RULE.md) | **Primary:** do not break pqcrypto↔OpenSSL/BoringSSL/liboqs/AWS-LC byte-exactness |
| [CLAIM_BOUNDARY.md](doc/CLAIM_BOUNDARY.md) | Allowed vs forbidden wording |
| [API.md](doc/API.md) | Public surface and profile cheat-sheet |
| [AGENTS.md](AGENTS.md) | Mission-critical coding rules |
| [VM_COMPILER_BOUNDARY.md](doc/VM_COMPILER_BOUNDARY.md) | What the library vs the VM controls |

Further: [Architecture](doc/ARCHITECTURE.md) · [Agent brief](doc/AGENT_BRIEF.md) ·
[Consumer / pqcrypto migration](doc/CONSUMER_API_AND_MIGRATION.md) ·
[FN-DSA integer math](doc/FN_DSA_MATH.md) · [FIPS alignment](doc/FIPS_ALIGNMENT.md) · [pqcrypto reuse](doc/PQCRYPTO_REUSE.md) ·
[Testing](doc/TESTING.md) · [Reduction](doc/REDUCTION.md) · [Roadmap](doc/ROADMAP.md) ·
[Security posture](doc/SECURITY_POSTURE.md) · [Benchmarks](doc/BENCHMARKS.md) ·
[Table provenance](doc/TABLE_PROVENANCE.md) · [SDK constraints](doc/SDK_CONSTRAINTS.md) ·
[SDK SIMD tracking](doc/SDK_SIMD_TRACKING.md) · [Contributing](CONTRIBUTING.md)

**License:** MIT (see [LICENSE](LICENSE)).

---

## Status (`0.1.0-dev`)

| Area | State |
| ---- | ----- |
| Package layout, claims, AGENTS, API docs | **In place** |
| Ring presets (ML-KEM, ML-DSA, FN-DSA-512/1024) | **In place** |
| `ModQ`, schoolbook oracle, Poly / PolyVec / PolyMat | **Usable** (schoolbook real; others structural) |
| Barrett params / reduce | **Ready** for 3329 / 12289 / 8380417 |
| Montgomery | **Ready** for 3329 / 12289 / 8380417; opt-in via `montgomeryParams`; not default |
| NTT / iNTT | **Real** for ML-KEM, ML-DSA, FN-DSA-512/1024; L2 roundtrip + L3 basemul-vs-schoolbook + linearity green for all profiles; in-place APIs |
| `Basemul.mlKemPairs` | **Implemented** (fused Barrett) |
| `Basemul.pointwise` | **Implemented** (coeff-wise; for complete-style NTT) |
| Acceleration | **Default on** — Barrett (q=3329), optimized NTT; SIMD when capable |

Path A (analyze + tests green on the scaffold) is met. Path B (real zetas,
Barrett, NTT round-trip, profile-correct products) gates are green for all
shipped profiles — see [AGENT_BRIEF.md](doc/AGENT_BRIEF.md) and
[doc/NTT_BOUNDS.md](doc/NTT_BOUNDS.md).

---

## Ring profiles

| Preset | \(q\) | \(n\) | NTT-domain product |
| ------ | ----- | ----- | ------------------ |
| `RingParams.mlKem` | 3329 | 256 | **`Basemul.mlKemPairs`** (incomplete NTT) |
| `RingParams.mlDsa` | 8380417 | 256 | `Basemul.pointwise` |
| `RingParams.fnDsa512` | 12289 | 512 | `Basemul.pointwise` |
| `RingParams.fnDsa1024` | 12289 | 1024 | `Basemul.pointwise` |

Using `pointwise` for ML-KEM is **incorrect** relative to FIPS 203-style
incomplete NTT. FN-DSA support here is **integer** \(q\)-NTT only — not floating-point
FFT, Gaussian sampling, or full FN-DSA (see [FN_DSA_MATH.md](doc/FN_DSA_MATH.md)).

---

## Features

| Area | Types | Notes |
| ---- | ----- | ----- |
| Modular arithmetic | `ModQ`, `BarrettParams`, `MontgomeryParams` | `%` reference; Barrett primary target; Montgomery ready, opt-in |
| Polynomials | `Poly`, `PolyOps`, `PolyVec`, `PolyMat` | Dense coeffs; vectors/matrices for scheme-facing layouts |
| Schoolbook oracle | `RingMul` | Negacyclic product for tests / parity |
| NTT | `NttParams`, `NttEngine` | Per-profile factories; vector forward/inverse helpers |
| Basemul | `Basemul` | Profile-split API (`mlKemPairs` vs `pointwise`) |
| Kernels | `KernelMode`, `LatticeKernels` | **Default `accelerated`**; reference for oracles only |

- **100% pure Dart** on the core path — no FFI for lattice math.
- **Jurisdictional APIs** — one primary responsibility per type; no god-object.
- **Consumer-ready shape** — designed so `pqcrypto` can replace in-tree poly/NTT
  without moving Fujisaki–Okamoto or packing into this package.

---

## Claim boundary (summary)

| Allowed | Not allowed |
| ------- | ----------- |
| Pure-Dart NTT / polynomial arithmetic for lattice PQC | “FIPS 140 validated” / “CMVP certified” |
| Algebra aligned with rings used by FIPS 203 / 204 / FN-DSA integer params | “Implements ML-KEM / ML-DSA / FN-DSA” as full algorithms |
| Optional SIMD-aware kernels; scalar fallback always available | “Guaranteed constant-time on all backends” |
| Unit-tested math properties (reduction, round-trip, oracles) | “NIST KAT byte-exact” for a full standard (that’s the scheme package) |

Full text: [doc/CLAIM_BOUNDARY.md](doc/CLAIM_BOUNDARY.md).

---

## Quick start

```dart
import 'package:pqlattice/pqlattice.dart';

void main() {
  // --- ML-KEM ring (incomplete NTT → pair basemul) ---
  final kem = RingParams.mlKem; // q = 3329, n = 256
  final nttKem = NttEngine(kem, params: NttParams.mlKem());

  final a = Poly.zero(kem);
  final b = Poly.zero(kem);
  // fill a.coeffs / b.coeffs in [0, q) ...

  final aHat = nttKem.forward(a);
  final bHat = nttKem.forward(b);
  // Path B: Basemul.mlKemPairs(aHat, bHat, kem) — not pointwise
  // final cHat = Basemul.mlKemPairs(aHat, bHat, kem);
  // final c = nttKem.inverse(cHat);

  // --- FN-DSA integer ring (complete-style NTT → pointwise) ---
  final fn = RingParams.fnDsa512; // q = 12289, n = 512
  final nttFn = NttEngine(fn, params: NttParams.fnDsa512());
  final h = Poly.zero(fn);
  final s2 = Poly.zero(fn);
  final hHat = nttFn.forward(h);
  final s2Hat = nttFn.forward(s2);
  final prodHat = Basemul.pointwise(hHat, s2Hat, fn);
  final prod = nttFn.inverse(prodHat);

  // Schoolbook oracle (any matching ring) for tests:
  // RingMul.schoolbookNegacyclic(a, b, kem);

  // While NttParams.zetas is empty, forward/inverse are identity placeholders.
}
```

Stable intent: **ring / mod / poly / ntt / basemul / kernels**. Method detail may
tighten through Path B; profile-correct basemul choice will not.

---

## Acceleration & SIMD

| `KernelMode` | Behavior |
| ------------ | -------- |
| **`accelerated`** (default) | Best available: SIMD if capable, else optimized scalar |
| `optimizedScalar` | Barrett/structured NTT without SIMD |
| `simd` | Prefer SIMD kernels when available |
| `reference` | Oracle / debug only (`%`, simple loops) |

Acceleration is **why this package exists** — [ACCELERATION.md](doc/ACCELERATION.md) · [Coeff storage](doc/COEFF_STORAGE.md).
SIMD is one accelerator, not an opt-in feature flag for “real” math. Not compiler
auto-vectorization. Interop-safe: [INTEROP_AND_FIPS_RULE.md](doc/INTEROP_AND_FIPS_RULE.md).
VM limits: [VM_COMPILER_BOUNDARY.md](doc/VM_COMPILER_BOUNDARY.md).
Upstream Dart SIMD issues (pairwise `Int32x4 *`, tracking): [SDK_SIMD_TRACKING.md](doc/SDK_SIMD_TRACKING.md).

---

## Stack

```text
zeroize        secret lifetime + narrow CT helpers
    ↑
pqlattice      NTT, mod q, polynomials, optional SIMD   ← this package
    ↑
pqcrypto       ML-KEM / ML-DSA / SLH-DSA (+ future FN-DSA scheme logic)
    ↑
pqforge / pqtransport
```

- **`zeroize`** — not a home for NTT math.
- **`pqlattice`** — reusable lattice arithmetic only.
- **`pqcrypto`** — algorithms, FO (ML-KEM), packing, sampling, KAT/ACVP evidence.

---

## Installation

```yaml
dependencies:
  pqlattice: ^0.1.0-dev.1
```

```dart
import 'package:pqlattice/pqlattice.dart';
```

Until the first stable publish, use a path or git dependency.

---

## Development

```bash
dart pub get
dart analyze
dart test
dart format .
```

Rules and workflow: [AGENTS.md](AGENTS.md).  
Success paths: [doc/AGENT_BRIEF.md](doc/AGENT_BRIEF.md).

---

## License

MIT — see [LICENSE](LICENSE).

## Author

Turkana Nation — [yardenah.com](https://yardenah.com) ·
[github.com/turkananation](https://github.com/turkananation)
