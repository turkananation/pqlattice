# SDK Constraints & Feature Adoption

Last updated: 2026-10-27

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

---

## 2. Feature matrix (Dart `typed_data` / VM)

| Feature | Approx. availability | `pqlattice` use |
|---------|----------------------|-----------------|
| `Int32x4` `+` `-` `&` `\|` `^` | Long-standing | SIMD shape loads/arithmetic |
| AOT specialization improvements | Ongoing (see SDK issues) | Measure; don’t assume |
| `Int32x4` shifts, `min`/`max`, `andNot`, compares, `splat` | Landing under SDK SIMD tracking (#64170) | Use when min SDK guarantees them **or** guard |
| **`Int32x4 operator *`** | **Open** (#59816) | Not used until shipped; keep scalar lane mul |
| Relaxed SIMD / Wasm extras | #64216 | No native default dependency |

Exact version numbers for shifts/min/max must be filled when they hit a
**stable** release you depend on—update this table in the same PR that
raises `sdk:` or adds guards.

---

## 3. Adoption patterns

### A. Raise `environment.sdk`

Use when the new op is required on all builds.

```yaml
environment:
  sdk: ^3.XX.0   # first stable with Int32x4.*
```

### B. Conditional code (preferred during transition)

```dart
// Conceptual — implement with a single capability helper, not scattered checks
bool get supportsInt32x4Mul => /* SDK version or probe */;

Int32x4 product(Int32x4 a, Int32x4 b) {
  if (supportsInt32x4Mul) {
    return a * b; // only compile/call when SDK has operator *
  }
  return Int32x4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w);
}
```

Until the language/analyzer knows `operator *`, keep the true-mul path in a
version-gated library or defer entirely to post-upgrade PR.

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
[ ] Do not call Int32x4 * until SDK_SIMD_TRACKING snapshot says available
[ ] Any sdk: constraint bump → update this file + CHANGELOG
[ ] Prefer parity tests over assuming intrinsification quality
```
