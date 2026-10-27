import 'dart:typed_data';

import '../ring/ring_params.dart';

/// Scalar coefficient type on the hot path: plain Dart [int] (no [BigInt]).
///
/// Values are reduced into \([0, q)\) or a documented centered range by [ModQ].
typedef Coeff = int;

/// Dense coefficient buffer (logical view). Prefer allocating via [CoeffBuffer].
typedef CoeffList = List<int>;

/// Physical width of a packed coefficient lane for accelerated storage / SIMD.
///
/// **Not** a hierarchy of “Int8 class / Int16 class” objects per coefficient —
/// Dart’s cost model wants **typed data vectors** + scalar [int] ops in [ModQ].
///
/// | Width | Typed data | Typical use |
/// | ----- | ---------- | ----------- |
/// | [CoeffWidth.i16] | [Int16List] | ML-KEM \(q=3329\), FN-DSA \(q=12289\) reduced coeffs |
/// | [CoeffWidth.i32] | [Int32List] | ML-DSA \(q=8380417\); wide intermediates |
/// | [CoeffWidth.i64] | [Int64List] | Rare staging; prefer avoid on hot path |
///
/// **[CoeffWidth.i8] / [Int8List]:** too narrow for any FIPS profile modulus
/// once values are in \([0,q)\) (e.g. 3329 > 255). Reserved only for specialized
/// compressed or toy representations — not default poly storage.
enum CoeffWidth {
  /// 8-bit lanes — **not** default for ML-KEM / ML-DSA / FN-DSA polys.
  i8,

  /// 16-bit lanes — default for \(q < 2^{15}\) profiles (ML-KEM, FN-DSA).
  i16,

  /// 32-bit lanes — default for ML-DSA and general intermediates.
  i32,

  /// 64-bit lanes — staging only.
  i64,
}

/// Chooses a storage width from ring parameters (reduced coefficients).
final class CoeffLayout {
  CoeffLayout._();

  /// Default packed width for coefficients already reduced mod [ring.q].
  static CoeffWidth widthFor(RingParams ring) {
    final q = ring.q;
    if (q <= 0) {
      throw ArgumentError.value(q, 'q');
    }
    // Need signed range at least [0, q) or centered (-q/2, q/2].
    if (q <= 0x7fff) return CoeffWidth.i16; // 3329, 12289
    if (q <= 0x7fffffff) return CoeffWidth.i32; // 8380417
    return CoeffWidth.i64;
  }

  /// Whether [width] can hold reduced residues for [ring.q].
  static bool fitsReduced(RingParams ring, CoeffWidth width) {
    final q = ring.q;
    switch (width) {
      case CoeffWidth.i8:
        return q <= 0x7f;
      case CoeffWidth.i16:
        return q <= 0x7fff;
      case CoeffWidth.i32:
        return q <= 0x7fffffff;
      case CoeffWidth.i64:
        return true;
    }
  }
}

/// Allocates **contiguous** coefficient buffers for accelerated kernels.
///
/// Returns a [List]-compatible typed data list so existing [Poly] / NTT code
/// can index with `[]` while SIMD paths get a real [Int16List] / [Int32List].
final class CoeffBuffer {
  CoeffBuffer._();

  /// Zero-filled buffer of length [n] using [width] (default from [ring]).
  static List<int> zeros(RingParams ring, {CoeffWidth? width}) {
    final w = width ?? CoeffLayout.widthFor(ring);
    if (!CoeffLayout.fitsReduced(ring, w)) {
      throw ArgumentError(
        'CoeffWidth.$w cannot hold reduced residues for q=${ring.q}',
      );
    }
    final n = ring.n;
    switch (w) {
      case CoeffWidth.i8:
        return Int8List(n);
      case CoeffWidth.i16:
        return Int16List(n);
      case CoeffWidth.i32:
        return Int32List(n);
      case CoeffWidth.i64:
        return Int64List(n);
    }
  }

  /// Copy [values] into a typed buffer of [width] (default from [ring]).
  static List<int> fromList(
    RingParams ring,
    List<int> values, {
    CoeffWidth? width,
  }) {
    if (values.length != ring.n) {
      throw ArgumentError(
        'expected ${ring.n} coefficients, got ${values.length}',
      );
    }
    final buf = zeros(ring, width: width);
    for (var i = 0; i < values.length; i++) {
      buf[i] = values[i];
    }
    return buf;
  }

  /// True if [list] is a typed-data list (contiguous).
  static bool isTyped(List<int> list) =>
      list is Int8List ||
      list is Int16List ||
      list is Int32List ||
      list is Int64List;
}
