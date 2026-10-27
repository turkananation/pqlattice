# VM & Compiler Boundary

Last updated: 2026-10-27

This document records **what pure-Dart code in `pqlattice` can guarantee** and
**what only the Dart VM / compilers can change**. It is factual posture for
agents and reviewers—not a feature request list presented as current capability.

Related: [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md), [ARCHITECTURE.md](ARCHITECTURE.md),
[SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md) (upstream issue register + adoption plan).

---

## 1. Purpose

Lattice workloads (NTT, modular mul/reduce, basemul, poly vector ops) are
integer-heavy and parallelizable. Performance and side-channel posture depend
on both **algorithms in this package** and **code generation** on the Dart VM
(JIT/AOT), dart2js, and dart2wasm.

`pqlattice` must remain correct and portable when the VM does not vectorize,
does not intrinsify SIMD well under AOT, or runs on the web.

---

## 2. What this library controls

| Area | Library responsibility |
| ---- | ---------------------- |
| Algorithms | NTT shape (incomplete vs complete), twiddle layout, lazy reduction bounds, Barrett/Montgomery *recipes* when implemented |
| Data layout | Coefficient storage (`List<int>` / future `Int32List`), `Poly` / `PolyVec` shape |
| Explicit SIMD kernels | Optional hand-written paths using `dart:typed_data` vector types; bit-identical to scalar |
| Fallback policy | `KernelMode.scalar` \| `simd` \| `auto`; scalar is always correct |
| Testing | Unit properties, scalar↔SIMD parity, reduction bounds—not full NIST KATs for KEMs |
| Documentation honesty | No claim that auto-vectorization or AOT SIMD will match C/assembly |

---

## 3. What this library does **not** control

| Area | Reality (Dart as of this writing) |
| ---- | --------------------------------- |
| **Auto-vectorization** | Scalar NTT/basemul loops are **not** reliably turned into SIMD by the Dart compilers the way mature C toolchains sometimes auto-vectorize. **Do not depend on auto-vectorization** for speed or for any correctness story. |
| **AOT intrinsification of SIMD** | Types such as `Int32x4` / `Float32x4` may perform well under the adaptive **JIT** and substantially worse under **AOT** (`dart compile exe`, Flutter release) when intrinsification, unboxing, or register allocation lag. Treat SIMD speedups as **measured, target-specific**, not portable guarantees. |
| **Richer integer SIMD ISA surface** | The public SIMD API is limited (effectively 128-bit-oriented value types). There is no first-class portable `Int16x8` / wide AVX-style surface in the language for library authors to assume. |
| **Modular-mul recognition** | The backend does not specially lower “Montgomery/Barrett sequences” the way some C compilers lower recognized patterns. Reduction cost is dominated by what **we emit** in Dart. |
| **GC and zeroization** | The scavenger may copy buffers; best-effort overwrite is not OS-locked secret memory. Secret lifetime policy belongs with `zeroize` / callers—see claim boundary. |
| **JS / Wasm timing** | Source-level “constant-time” structure does not guarantee constant-time execution on dart2js or dart2wasm. |

---

## 4. Integer arithmetic posture

- **Hot path:** Dart `int` (fit intermediates in signed 63-bit practice where
  possible) and/or typed data (`Int32List`, etc.).
- **Do not** use `BigInt` in NTT, basemul, or modular mul loops.
- **Document** maximum intermediate magnitude when using lazy reduction so
  implementations stay within safe `int` range for the chosen \(q\).
- Optional named helpers (`freeze`, `csubq`, centered reps) live in `ModQ` /
  poly ops—not a separate heavyweight numeric tower.

---

## 5. Modular reduction strategies

| Strategy | Library status | Notes |
| -------- | -------------- | ----- |
| Division / `%` | Baseline via `ModQ.reduce` | Correct reference; fine for tests and early scaffolds |
| **Barrett** | `BarrettParams` + `ModQ.reduceBarrett` | Intended primary optimized path for fixed small \(q\) (e.g. 3329). Fill \(\mu\) and bounds before claiming optimization. |
| **Montgomery** | `MontgomeryParams` scaffold | **Deferred** for performance work after Barrett NTT is correct. Domain conversion must be explicit. |
| Lazy reduction | Documented intent on NTT butterflies | Algorithmic; no VM feature required |

None of these are “FIPS validated modular arithmetic modules.”

---

## 6. Acceleration vs VM limits (SIMD is one accelerator)

Acceleration is **on by default** at the library level (Barrett, NTT structure,
layout, SIMD when available). See [ACCELERATION.md](ACCELERATION.md).

1. Optimized accelerated kernels are the **product default**.
2. Reference (`%`, schoolbook) kernels are for **oracles and debug**.
3. SIMD kernels must match optimized scalar on the same inputs (parity).
4. Under `KernelMode.accelerated`, use SIMD when `SimdCapability.isLikelyBeneficial`
   and parity tests cover the target build class; otherwise optimized scalar.
5. Capability may stay false until AOT evidence exists — that only disables SIMD,
   not Barrett/NTT acceleration.
6. Public APIs never require callers to touch `Int32x4`.

**Forbidden:** “auto-vectorized NTT”, “guaranteed SIMD speedup on all platforms”.

**Required framing:** accelerated by default; SIMD when capable; interop-safe.

---

## 7. If the VM / language improves later

Improvements that would raise the ceiling (not promised by this package):

- Richer integer vector types and operations
- AOT intrinsification parity with JIT for existing SIMD types
- Better bounds-check elimination on tight typed-data loops
- Pattern lowering for modular multiply sequences

When those exist, `pqlattice` can add kernels behind the same `KernelMode`
facade without breaking jurisdictional APIs.

---

## 8. Non-claims (compiler/VM edition)

- Not a substitute for assembly NTT on AVX2/NEON/AVX-512.
- Not a guarantee of constant-time execution on any backend.
- Not a guarantee that Flutter release builds match VM JIT microbenchmarks.
- Not CMVP / FIPS 140 module validation (see [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md)).

---

## 9. Practical guidance for agents

1. Ship **accelerated** Barrett + NTT as the default path; gate on interop parity.
2. Do **not** block library acceleration on VM SIMD fixes.
3. Enable SIMD under accelerated mode only with parity tests + AOT notes.
4. Keep this file updated when SDK behavior is re-measured; do not soften
   non-claims without evidence.
