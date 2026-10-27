# Coefficient Storage (Int16 / Int32 lanes)

Last updated: 2026-10-27

## What was intended

Accelerated lattice math needs **packed coefficient lanes**, not a tree of
per-value integer *objects*. In Dart that means `dart:typed_data`:

| Lane | Type | Profiles |
| ---- | ---- | -------- |
| 16-bit | `Int16List` | ML-KEM (\(q=3329\)), FN-DSA (\(q=12289\)) |
| 32-bit | `Int32List` | ML-DSA (\(q=8380417\)) |
| 8-bit | `Int8List` | **Not** for reduced FIPS residues (\(3329 > 127\)) |
| 64-bit | `Int64List` | Staging only |

Scalar arithmetic stays on plain `int` via `ModQ` (`typedef Coeff = int`).

## API

- `CoeffWidth` — `i8` / `i16` / `i32` / `i64`
- `CoeffLayout.widthFor(ring)` — default width for reduced coeffs
- `CoeffBuffer.zeros` / `fromList` — allocate typed buffers
- `Poly.zero` / `fromCoeffs` — **default to packed storage** (acceleration default)

## Why not “class Int16 { ... }”

A wrapper class per coefficient would allocate and box on the hot path. The
acceleration model is: **contiguous typed arrays + `ModQ` on `int`**, with
optional `Int32x4` SIMD over those arrays later.
