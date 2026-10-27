# Dart SDK SIMD Tracking (for `pqlattice`)

Last updated: 2026-10-27  
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

`pqlattice` acceleration is **on by default**. Today the SIMD path is:

> **4-wide shape + packed storage + scalar lane mul**

because public `Int32x4` has **no** lane-wise `operator *`. Upstream is
actively extending `dart:typed_data` SIMD. When pairwise integer mul (and
related ops) land and are intrinsified in **AOT**, we retire the scalar-mul
bottleneck inside the 4-wide kernels—without FFI and without breaking
byte-exact interop.

---

## 2. Issue register

| ID | Title | Role for `pqlattice` | Priority |
|----|--------|----------------------|----------|
| [#64170](https://github.com/dart-lang/sdk/issues/64170) | **SIMD tracking issue** | Umbrella: additive `Int32x4` surface, AOT intrinsification, feature completeness | **P0 — watch** |
| [#59816](https://github.com/dart-lang/sdk/issues/59816) | **Support multiplication on Int32x4** | **True pairwise mul** — the kernel blocker for basemul / Barrett / Mont product | **P0 — unlock** |
| [#64216](https://github.com/dart-lang/sdk/issues/64216) | Relaxed SIMD (`dart2wasm` + typed_data) | Web/Wasm path; FMA-style ops; not a substitute for native integer mul | **P2 — secondary** |
| [#62618](https://github.com/dart-lang/sdk/issues/62618) | Richer / predictable SIMD APIs | Load/store, shuffle, blend; quality of life for kernels | **P1 — quality** |
| [#63471](https://github.com/dart-lang/sdk/issues/63471) | Int8x16 / narrower lanes | Future packing density; not required for current ML-KEM/ML-DSA/FN-DSA i32 paths | **P3 — later** |

### Snapshot (as of 2026-10-27)

| Capability | Upstream status | `pqlattice` posture |
|------------|-----------------|---------------------|
| `Int32x4` `+` `-` `&` `\|` `^` | Present; AOT specialization improved under tracking work | Used in SIMD-shaped kernels |
| Shifts `<<` `>>` `>>>` | Added under #64170 trajectory | Use for Barrett/Montgomery shifts when available on min SDK |
| `min` / `max` / `andNot` / compares / `splat` | Landing under #64170 | Optional for clamp / mask patterns |
| **`Int32x4 operator *` (32-bit wrap)** | **Open** (#59816); explicitly called out as blocker on #64170 | **Still 4-wide + scalar mul** |
| Relaxed SIMD / Wasm | Open (#64216); browser baseline concerns | Ignore for native-first crypto path until stable |
| AOT vs JIT parity for SIMD | Ongoing fixes under tracking + related issues | Measure both; never claim portable SIMD speedups |

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
[ ] Local: dart --version; if newer than last check, run tool/bench + SIMD parity tests AOT
[ ] Update Snapshot table + "Last reviewed" below
[ ] If mul landed: open pqlattice issue/PR per §4 (do not land without parity)
```

**Last reviewed:** 2026-10-27  
**Next review due:** 2026-11-10  

### How to verify mul if it appears in a dev SDK

```bash
# Compile a 4-line probe (or use test/simd_pointwise_parity_test.dart extended)
dart compile exe tool/bench/ntt_bench.dart -o /tmp/ntt_bench
/tmp/ntt_bench

# Parity (must remain bit-identical to scalar/Barrett path)
dart test test/simd_pointwise_parity_test.dart
```

Confirm **AOT** and **JIT**. JIT-only wins do not change the default kernel.

---

## 4. How `pqlattice` changes when upstream moves

### 4.1 When `Int32x4 operator *` lands (stable or pinned min SDK)

| Step | Action | Success criteria |
|------|--------|------------------|
| 1 | Extend `lib/src/simd/` pointwise / basemul path to use `a * b` (lane-wise) | Same residues as scalar oracle |
| 2 | Keep **scalar mul fallback** for older SDKs (`sdk` constraint or capability flag) | CI on oldest supported SDK still green |
| 3 | Barrett/Montgomery product steps: prefer vector mul + existing vector shifts | Interop rule unchanged ([INTEROP_AND_FIPS_RULE.md](INTEROP_AND_FIPS_RULE.md)) |
| 4 | Update [SIMD.md](SIMD.md) § “What SIMD means” — remove “no pairwise mul” | Doc matches code |
| 5 | Bench AOT: report before/after in PR; do **not** claim universal speedup | Numbers on x64 + arm64 if available |
| 6 | `KernelMode.accelerated` may prefer the true-mul path when parity-proven | Fail closed: parity fail → optimized scalar |

**Semantics we require from upstream (document in PR if unclear):**

- Lane-wise product  
- **Low 32 bits** (wrapping), matching hardware 32×32→32 low half  
- Identical on VM AOT, JIT, and other backends we claim to support  

Widening / high-half mul is **out of scope** for the first adoption; optional later.

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
| Future `dart2wasm` optional path | Separate experiment; must still pass residue parity |
| Document in this file only until a real consumer path exists | Yes |

### 4.4 What never changes because of SDK SIMD work

- **Byte-exact interop** with the pqcrypto / OpenSSL / BoringSSL / liboqs / AWS-LC style path  
- **FIPS ring parameters** and claim boundary (math-only package)  
- **No `dart:ffi`** on the pure-Dart acceleration path  
- **Scalar / reference oracles** remain the correctness source of truth  

---

## 5. Engagement with upstream (optional but useful)

If commenting on #59816 or #64170, keep the ask **narrow**:

1. Use case: integer NTT / basemul / Barrett for PQC rings (exact int products).  
2. Why not `Float32x4`: intermediates exceed exact float32 integer range.  
3. Requested API: `Int32x4 operator *` with **32-bit wrap** per lane.  
4. Offer: minimal AOT microbench + parity test from this package.

Do **not** demand language changes, new syntax, or breaking changes to existing operators.

---

## 6. Owner checklist for agents

```text
On any session that touches SIMD kernels or ACCELERATION/SIMD docs:
  1. Read this file (Snapshot + Last reviewed).
  2. If review is overdue, run §3 checklist and update dates.
  3. Do not implement "true pairwise mul" until §2 shows #59816 done
     or a shipped SDK documents Int32x4 *.
  4. Any kernel change: scalar parity test required before merge.
```

---

## 7. History log

| Date | Note |
|------|------|
| 2026-10-27 | Initial register: #64170, #59816, #64216, #62618, #63471. Pairwise mul still open. Shape remains 4-wide + scalar mul. |

Append a row on every formal review or when an issue closes.
