# SDK Constraints & Feature Adoption

Last updated: 2026-11-13

How `pqlattice` relates to **Dart SDK versions** and optional SIMD surface
without breaking older consumers or inventing APIs.

Related: [SDK_SIMD_TRACKING.md](SDK_SIMD_TRACKING.md), [SIMD.md](SIMD.md),
[pubspec.yaml](../pubspec.yaml).

---

## 1. Current constraint

```yaml
environment:
  sdk: ^3.13.0
```

Adjust only with CI proof on the new lower/upper bound. Prefer **raising**
minimum when adopting APIs that do not exist on older SDKs—not silent
runtime crashes.

The shipped SIMD kernel deliberately uses only the long-standing `Int32x4`
surface (`+`, `-`, `>>`, `&`, four-argument constructor), so `^3.13.0` is
still accurate even though the measurement host runs 3.14.0.

---

## 2. Feature matrix (Dart `typed_data` / VM)

| Feature | Availability | `pqlattice` use |
|---------|--------------|-----------------|
| `Int32x4` `+` `-` `&` `\|` `^` `~` unary `-` | Long-standing | **Used** — combine pass |
| `Int32x4` `<<` `>>` | Long-standing; `>>` is arithmetic (sign-propagating) | **Used** — `>> 31` builds the branchless negate mask |
| `Int32x4.min/max/andNot/equal/allTrue/anyTrue` | Long-standing | Available; not needed |
| `Int32x4 >>>` (logical shift) | **3.14.0** | Not used — would force an `sdk:` bump for no gain |
| `Int32x4.splat` | **3.14.0** | **Not used** — `Int32x4(q, q, q, q)` gives identical codegen and keeps `^3.13.0` |
| **`Int32x4 operator *`** | **3.15.0 main only**; no VM graph intrinsic yet (#59816, #64170) | Not used. Lane-wise 32-bit wrap cannot carry ML-DSA `q² ≈ 2^46`, so it is a future **basemul** lever, not an NTT one |
| Relaxed SIMD / Wasm extras | #64216, open | No native default dependency |

Exact version numbers for `>>>` and `splat` were confirmed against the
3.14.0 / 3.15.0 stable and dev CHANGELOGs; re-check before changing the
`Int32x4` surface used by `lib/src/simd/`.

---

## 3. Adoption patterns

### A. Raise `environment.sdk`

Use when the new op is required on all builds.

```yaml
environment:
  sdk: ^3.XX.0   # first stable with Int32x4.*
```

### B. Conditional code

Prefer a **single capability helper** (`SimdCapability`) over scattered
checks. Do **not** write a runtime `supportsInt32x4Mul` probe: `operator *`
is a compile-time API, so a probe cannot both compile on older SDKs and
select it at runtime. Either raise the constraint or keep the scalar form.

```dart
// Shipped pattern: one gate, one kernel, no per-op probes.
final simd = LatticeKernels.preferSimdNtt(mode, ring, inverse: false);
```

### C. Document-only

If an op is rare (e.g. Wasm-only), document under SDK_SIMD_TRACKING and do
not complicate the native default path.

---

## 4. CI expectation

| Job | Purpose |
|-----|---------|
| Analyze + test on **min SDK** | No accidental use of newer APIs |
| Test on **current stable** | Forward health |
| Optional AOT bench on stable | Perf signals |

---

## 5. Agent rule

```text
[ ] Do not call Int32x4 * until SDK_SIMD_TRACKING snapshot says it has a
    shipped stable release AND a VM graph intrinsic
[ ] Any sdk: constraint bump → update this file + CHANGELOG
[ ] Prefer parity tests over assuming intrinsification quality
[ ] Do not add a runtime probe for a compile-time API
```