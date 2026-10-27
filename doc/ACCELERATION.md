# Acceleration is First-Class (Default On)

Last updated: 2026-10-27

## Why this package exists

`pqlattice` exists to make lattice / polynomial math **fast** for consumers
(`pqcrypto` and others) **without breaking** FIPS-aligned algebra or
`pqcrypto`’s byte-exact interop with OpenSSL, BoringSSL, liboqs, and AWS-LC.

Acceleration is **not** an optional add-on. It is the **product**.

| Path | Role |
| ---- | ---- |
| **Accelerated (default)** | Barrett (and later Montgomery where beneficial), optimized NTT/basemul, contiguous layouts, SIMD kernels when the backend can run them |
| **Reference** | `%` reduce, schoolbook mul, scalar-only loops | **Tests, oracles, debugging** — not the design-center hot path |

Public APIs and defaults must point at the **accelerated** path. Reference
kernels remain available for parity tests and for environments where a given
accelerator cannot run; they are not the story of the package.

---

## What “on by default” means

1. **Modular reduce on hot paths** uses Barrett (or the profile’s chosen
   accelerator) when parameters are ready — not `%` in NTT/basemul inner loops.
2. **NTT / basemul** ship as optimized implementations (tables, structure,
   reduction strategy chosen for speed under interop constraints).
3. **Kernel selection defaults to accelerated**: use the best available
   accelerated kernel (SIMD when capable, else optimized scalar). Callers do
   not opt in to “go fast.”
4. **Interop / FIPS remain constraints on the accelerated path** — not reasons
   to keep the library slow. See [INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md).

---

## SIMD control and flip

See **[SIMD.md](SIMD.md)** for:

- What SIMD means on the Dart VM (`Int32x4` shape, no pairwise mul)
- How to flip: `KernelMode.accelerated` (default) / `simd` / `optimizedScalar` / `reference`
- Parity and interop invariants
- Where kernels apply today (pointwise helper; NTT butterflies remain optimized scalar)

## Barrett (and friends)

- Barrett for \(q = 3329\) is **first-class field acceleration**, ready and
  intended for mul/reduce in ML-KEM-shaped code.
- `%` remains the **correctness oracle** in tests.
- Aligning Barrett constants with `pqcrypto` is driven by **interop parity**,
  not by demoting Barrett to “optional.”
- Further accelerators (Montgomery, lazy reduction, profile-specific reduce)
  are adopted as **default** once parity-gated — not hidden behind flags.

---

## SIMD

- SIMD is part of the **default acceleration stack** when
  `SimdCapability` says the build can use it profitably and parity tests pass.
- It is **not** “optional marketing.” It is **not** compiler auto-vectorization.
- Where SIMD cannot run (some AOT/web targets), the default falls back to
  **optimized scalar** — still accelerated relative to naive code — not to a
  deliberately slow educational path.
- VM limits are documented in [VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md);
  they constrain *how* we accelerate, not *whether* acceleration is the goal.

---

## API posture

```text
Default:  KernelMode.accelerated  (best available: SIMD → optimized scalar)
Explicit: KernelMode.reference    (oracle / debug only)
```

Legacy names `auto` / `scalar` / `simd` map into this model for compatibility;
documentation leads with **accelerated by default**.

---

## Non-goals

- Claiming guaranteed speedups on every Dart backend
- Shipping wrong math for speed
- Making callers pass `fast: true` to get the real implementation


## Implementation status (efficiency)

| Item | Status |
| ---- | ------ |
| Packed Int16/Int32 coeffs | Yes |
| Barrett q=3329, 12289, 8380417 | Yes — default mul-reduce |
| addFast / subFast in NTT | Yes |
| ML-KEM NTT + pair basemul | Yes (in-place APIs) |
| ML-DSA NTT | Yes (pqcrypto tables) |
| FN-DSA NTT | Pending zetas |
| SIMD pointwise | Implemented; enable via SimdCapability after AOT |
| Bench | `tool/bench/ntt_bench.dart` |
