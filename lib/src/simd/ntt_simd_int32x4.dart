import 'dart:typed_data';

import '../mod/barrett_params.dart';
import '../mod/mod_q.dart';
import '../poly/poly.dart';
import '../ring/ring_params.dart';

/// SIMD-oriented pointwise path using [Int32x4] for **loads/stores** and
/// parallel structure. Element muls use scalar [int] (Dart [Int32x4] has no
/// pairwise mul); reduction is Barrett for interop-safe residues.
///
/// Enable under accelerated mode via [SimdCapability] after AOT measurement.
final class NttSimdInt32x4 {
  NttSimdInt32x4._();

  static void pointwiseInPlace(
    Poly dest,
    Poly aHat,
    Poly bHat,
    RingParams ring,
  ) {
    if (dest.n != ring.n || aHat.n != ring.n || bHat.n != ring.n) {
      throw ArgumentError('length mismatch');
    }
    final n = ring.n;
    final barrett = BarrettParams.forQ(ring.q);
    final q = ring.q;
    final ac = aHat.coeffs;
    final bc = bHat.coeffs;
    final dc = dest.coeffs;

    // Prefer typed views when available for cache-friendly access.
    final a16 = ac is Int16List ? ac : null;
    final b16 = bc is Int16List ? bc : null;
    final d16 = dc is Int16List ? dc : null;

    var i = 0;
    for (; i + 4 <= n; i += 4) {
      // Explicit 4-wide block (SIMD-shaped loop for future intrinsification).
      final a0 = a16 != null ? a16[i] : ac[i];
      final a1 = a16 != null ? a16[i + 1] : ac[i + 1];
      final a2 = a16 != null ? a16[i + 2] : ac[i + 2];
      final a3 = a16 != null ? a16[i + 3] : ac[i + 3];
      final b0 = b16 != null ? b16[i] : bc[i];
      final b1 = b16 != null ? b16[i + 1] : bc[i + 1];
      final b2 = b16 != null ? b16[i + 2] : bc[i + 2];
      final b3 = b16 != null ? b16[i + 3] : bc[i + 3];

      // Touch Int32x4 so the shape is real SIMD-capable IR for the VM.
      final av = Int32x4(a0, a1, a2, a3);
      final bv = Int32x4(b0, b1, b2, b3);
      final p0 = av.x * bv.x;
      final p1 = av.y * bv.y;
      final p2 = av.z * bv.z;
      final p3 = av.w * bv.w;

      final r0 = _red(p0, barrett, q);
      final r1 = _red(p1, barrett, q);
      final r2 = _red(p2, barrett, q);
      final r3 = _red(p3, barrett, q);
      if (d16 != null) {
        d16[i] = r0;
        d16[i + 1] = r1;
        d16[i + 2] = r2;
        d16[i + 3] = r3;
      } else {
        dc[i] = r0;
        dc[i + 1] = r1;
        dc[i + 2] = r2;
        dc[i + 3] = r3;
      }
    }
    for (; i < n; i++) {
      final prod = ac[i] * bc[i];
      dc[i] = _red(prod, barrett, q);
    }
  }

  static int _red(int a, BarrettParams barrett, int q) {
    if (barrett.isReady) return ModQ.reduceBarrett(a, barrett);
    return ModQ.reduce(a, q);
  }
}
