# Dart SDK SIMD Tracking (for `pqlattice`)

Last updated: 2026-11-13  
Status review cadence: **every 2 weeks** (or after each Dart stable / notable dev SDK bump)

This document tracks **upstream Dart SDK work** that can change how far
`pqlattice` acceleration can go **without** leaving pure Dart. It defines:

1. Which GitHub issues matter and why
2. How to re-check progress
3. Exact package changes when a capability lands
4. What we do **not** change (interop / claim boundary)

Related: [SIMD.md](SIMD.md), [ACCELERATION.md](ACCELERATION.md),
[VM_COMPILER_BOUNDARY.md](VM_COMPILER_BOUNDARY.md), [SDK_CONSTRAINTS.md](SDK_CONSTRAINTS.md),
[BENCHMARKS.md](BENCHMARKS.md), [CLAIM_BOUNDARY.md](CLAIM_BOUNDARY.md).

---

## 1. Why this exists

`pqlattice` acceleration is **on by default** and the shipped SIMD path is:

> **scalar multiply-reduce pass per stage + 4-lane `Int32x4` butterfly combine**

This is a **two-pass stage**, not a fully vectorized butterfly: the
multiply-and-reduce half of each butterfly stays scalar (it needs exact
`int` products up to `q²`, which is 46 bits for ML-DSA), and the add/sub
half runs as `Int32x4` lanes with branchless canonicalization
`d + ((d >> 31) & q)`.

That split is deliberate and measured: it needs **no** lane-wise
`operator *`, only `+`, `-`, `>>`, `&`, and indexed load/store — all present
in the minimum SDK this package supports (`^3.13.0`). Measured gains are in
[SIMD.md](SIMD.md) §4.

Upstream `Int32x4 operator *` would let a future **basemul / pointwise**
kernel keep products in 32-bit lanes. It would **not** help the NTT
butterfly: lane-wise 32-bit low-half multiply is too narrow for ML-DSA's
`q² ≈ 2^46`, and it has no high-half variant.

---

## 2. Issue register

| ID | Title | Role for `pqlattice` | Priority |
|----|--------|----------------------|----------|
| [#64170](https://github.com/dart-lang/sdk/issues/64170) | **SIMD tracking issue** | Umbrella: additive `Int32x4` surface, AOT intrinsification, feature completeness | **P0 — watch** |
| [#59816](https://github.com/dart-lang/sdk/issues/59816) | **Support multiplication on Int32x4** | Would unlock a vectorized **basemul** path (32-bit wrap); cannot carry NTT butterfly products | **P1 — reduced** |
| [#64216](https://github.com/dart-lang/sdk/issues/64216) | Relaxed SIMD (`dart2wasm` + typed_data) | Web/Wasm path; FMA-style ops; not a substitute for native integer mul | **P2 — secondary** |
| [#62618](https://github.com/dart-lang/sdk/issues/62618) | Richer / predictable SIMD APIs | Load/store, shuffle, blend; quality of life for kernels | **P1 — quality** |
| [#63471](https://github.com/dart-lang/sdk/issues/63471) | Int8x16 / narrower lanes | Future packing density; not required for current ML-KEM/ML-DSA/FN-DSA i32 paths | **P3 — later** |

### Snapshot (as of 2026-11-13, Dart 3.14.0 stable)

| Capability | Upstream status | `pqlattice` posture |
|------------|-----------------|---------------------|
| `Int32x4` `+` `-` `&` `\|` `^` `~` unary `-` | Present, intrinsified | **Used** in the combine pass |
| Shifts `<<` `>>` `>>>` | `>>` arithmetic present everywhere; `>>>` added in **3.14.0** | Only `>>` is used, so min SDK stays `^3.13.0` |
| `min` / `max` / `andNot` / compares / `allTrue` / `anyTrue` | Present | Available; not needed by the current kernel |
| `Int32x4.splat` | Added in **3.14.0** | **Not used** — `Int32x4(q, q, q, q)` keeps min SDK at `^3.13.0` with identical codegen |
| `Int32x4 operator *` (32-bit wrap) | **Not in 3.14.0.** Present on SDK `main`, targeted at 3.15.0; **no `vm:recognized` graph intrinsic yet**, codegen still tracked under #64170 | Not needed by the NTT combine pass; would enable a future basemul path |
| Relaxed SIMD / Wasm | Open (#64216) | `v128` via `Int32x4` works on dart2wasm; **enabled but unmeasured** (see §4.3) |
| AOT vs JIT parity for SIMD | Improvement continues under tracking | Measured AOT only; JIT numbers are variance documentation, never claims |

Update the **Snapshot** table every review cycle. Do not claim a capability
in README or API docs until it is on a **stable** SDK we depend on (or
explicitly gated by SDK constraint + runtime detection).

---

## 3. Periodic progress check

### Cadence

- **Biweekly** during active kernel work  
- **After** every Dart **stable** release notes skim  
- **Ad hoc** when #59816 or #64170 gets a commit/comment mentioning multiply

### Checklist (copy into PR / agent log)

```text
[ ] Open #64170 — any new closed sub-items? CHANGELOG mention of Int32x4?
[ ] Open #59816 — still open? Any CL link for operator *?
[ ] sdk/CHANGELOG.md (dev or stable) — Int32x4 * / mul / min / shifts?
[ ] Local: dart --version; if newer than last check, run AOT SIMD benchmark
[ ] Update Snapshot table + "Last reviewed" below
[ ] If mul has a VM graph intrinsic: open pqlattice issue/PR per §4 (do not
    land without parity)
```

**Last reviewed:** 2026-11-13  
**Next review due:** 2026-11-27  

### How to verify a new `Int32x4` op

```bash
# AOT benchmark matrix (typed scalar vs split-pass vector, all profiles)
dart compile exe test/benchmarks/benchmarks_all.dart -o /tmp/pq_bench
/tmp/pq_bench --mode aot | awk -F'\t' 'NR==1 || $1=="simd"'

# Bit-exactness (merge gate, independent of timing)
dart test test/simd_ntt_parity_test.dart
```

Confirm **AOT**. JIT-only wins do not change the default kernel.

---

## 4. How `pqlattice` changes when upstream moves

### 4.1 When `Int32x4 operator *` lands with a real VM intrinsic

| Step | Action | Success criteria |
|------|--------|------------------|
| 1 | Prototype a 4-lane **pointwise / mlKemPairs** kernel — not the NTT butterfly | Same residues as the scalar oracle |
| 2 | Keep the scalar product for products exceeding 32 bits (ML-DSA `q² ≈ 2^46`) | No silent wraparound; document the bound |
| 3 | Bench AOT: report before/after in the PR; do **not** claim universal speedup | Numbers on x64 + arm64 if available |
| 4 | Update [SIMD.md](SIMD.md) §4 and this Snapshot table | Doc matches code |
| 5 | `KernelMode.accelerated` may prefer the vector product when parity-proven | Fail closed: parity fail → optimized scalar |

**Semantics we require from upstream (document in PR if unclear):**

- Lane-wise product  
- **Low 32 bits** (wrapping), matching hardware 32×32→32 low half  
- Identical on VM AOT, JIT, and other backends we claim to support  

Widening / high-half mul would be needed for a fully vectorized butterfly;
that is **out of scope** for the first adoption.

### 4.2 When only shifts / min / max / andNot land (no mul yet)

| Change | Allowed |
|--------|---------|
| Use shifts in Barrett/Montgomery **vector-shaped** code | Yes, if min SDK has them |
| Use `min`/`max` for clamp-style helpers | Yes, optional |
| Change default away from accelerated | **No** |
| Drop scalar parity tests | **No** |

### 4.3 When #64216 (relaxed SIMD / Wasm) progresses

| Change | Policy |
|--------|--------|
| Native VM kernels | **No** dependency |
| dart2wasm `Int32x4` | Enabled today via `SimdCapability`; **no measured speedup claim** — local Node 20 lacks wasm-gc, so the AOT wasm probe cannot run |
| dart2js | **Disabled.** Measured 0.37× (2.7× slower) on the split kernel |
| Document in this file only until a real consumer path exists | Yes |

### 4.4 What never changes because of SDK SIMD work

- **Byte-exact interop** with the pqcrypto / OpenSSL / BoringSSL / liboqs / AWS-LC style path  
- **FIPS ring parameters** and claim boundary (math-only package)  
- **No `dart:ffi`** on the pure-Dart acceleration path  
- **Scalar / reference oracles** remain the correctness source of truth  

---

## 5. Engagement with upstream (optional but useful)

If commenting on #59816 or #64170, keep the ask **narrow**:

1. Use case: integer basemul / pointwise products for PQC rings (exact int products).  
2. Why not `Float32x4`: intermediates exceed exact float32 integer range.  
3. Requested API: `Int32x4 operator *` with **32-bit wrap** per lane, plus a
   `vm:recognized` AOT intrinsic so it does not compile to lane extraction.  
4. Offer: minimal AOT microbench + parity test from this package.

Do **not** demand language changes, new syntax, or breaking changes to existing operators.

---

## 6. Owner checklist for agents

```text
On any session that touches SIMD kernels or ACCELERATION/SIMD docs:
  1. Read this file (Snapshot + Last reviewed).
  2. If review is overdue, run §3 checklist and update dates.
  3. Do not implement a vector product until §2 shows #59816 done AND a
     shipped SDK documents Int32x4 *.
  4. Any kernel change: bit-exact parity test required before merge.
  5. Any speed claim: AOT only, per-profile, with the hardware named.
```

---

## 7. History log

| Date | Note |
|------|------|
| 2026-10-27 | Initial register: #64170, #59816, #64216, #62618, #63471. Pairwise mul still open. Shape was 4-wide + scalar mul. |
| 2026-11-13 | Split-pass NTT kernels shipped. `operator *` re-scoped from "kernel blocker" to "future basemul only": lane-wise 32-bit wrap cannot carry ML-DSA `q² ≈ 2^46`. 3.14 surface confirmed (`splat`, `>>>`); avoided to keep min SDK `^3.13.0`. dart2js gated off (0.37×); dart2wasm enabled, unmeasured. |