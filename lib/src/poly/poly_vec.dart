import '../ring/ring_params.dart';
import 'poly.dart';

/// Fixed-length vector of polynomials over the same [RingParams].
///
/// Jurisdictional boundary: storage and length checks only. NTT-of-vector and
/// matrix–vector products live in engine/ops helpers that *use* this type.
final class PolyVec {
  final RingParams ring;

  /// Polynomials \(v_0, \ldots, v_{k-1}\).
  final List<Poly> polys;

  PolyVec._(this.ring, this.polys);

  /// [k] zero polynomials.
  factory PolyVec.zero(RingParams ring, int k) {
    if (k < 0) {
      throw ArgumentError.value(k, 'k', 'must be non-negative');
    }
    return PolyVec._(ring, List<Poly>.generate(k, (_) => Poly.zero(ring)));
  }

  /// Wraps existing polys; all must share [ring] sizes.
  factory PolyVec.fromPolys(RingParams ring, List<Poly> polys) {
    for (final p in polys) {
      if (p.n != ring.n || p.q != ring.q) {
        throw ArgumentError('poly ring mismatch');
      }
    }
    return PolyVec._(ring, List<Poly>.from(polys));
  }

  int get length => polys.length;

  Poly operator [](int i) => polys[i];

  PolyVec clone() =>
      PolyVec._(ring, polys.map((p) => p.clone()).toList(growable: false));
}
