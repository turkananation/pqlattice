import '../mod/barrett_params.dart';
import '../mod/mod_q.dart';
import 'poly.dart';

/// Coefficient-wise operations (no NTT).
final class PolyOps {
  PolyOps._();

  static void addInto(Poly dest, Poly a, Poly b) {
    _sameRing(dest, a, b);
    final q = dest.q;
    for (var i = 0; i < dest.n; i++) {
      dest.coeffs[i] = ModQ.add(a.coeffs[i], b.coeffs[i], q);
    }
  }

  static void subInto(Poly dest, Poly a, Poly b) {
    _sameRing(dest, a, b);
    final q = dest.q;
    for (var i = 0; i < dest.n; i++) {
      dest.coeffs[i] = ModQ.sub(a.coeffs[i], b.coeffs[i], q);
    }
  }

  static void negInto(Poly dest, Poly a) {
    if (dest.n != a.n || dest.q != a.q) {
      throw ArgumentError('ring mismatch');
    }
    final q = dest.q;
    for (var i = 0; i < dest.n; i++) {
      dest.coeffs[i] = ModQ.sub(0, a.coeffs[i], q);
    }
  }

  /// Reduce every coefficient into \([0, q)\) via [ModQ.reduce].
  static void reduceInto(Poly dest, Poly a) {
    if (dest.n != a.n || dest.q != a.q) {
      throw ArgumentError('ring mismatch');
    }
    final q = dest.q;
    for (var i = 0; i < dest.n; i++) {
      dest.coeffs[i] = ModQ.reduce(a.coeffs[i], q);
    }
  }

  /// Scale: \(dest_i = (k \cdot a_i) \bmod q\).
  static void scaleInto(Poly dest, Poly a, int k) {
    if (dest.n != a.n || dest.q != a.q) {
      throw ArgumentError('ring mismatch');
    }
    final q = dest.q;
    for (var i = 0; i < dest.n; i++) {
      dest.coeffs[i] = ModQ.mul(a.coeffs[i], k, q);
    }
  }

  /// Barrett-reduce every coefficient when params are ready.
  static void reduceBarrettInto(Poly dest, Poly a, BarrettParams params) {
    if (dest.n != a.n || dest.q != a.q || dest.q != params.q) {
      throw ArgumentError('ring / params mismatch');
    }
    for (var i = 0; i < dest.n; i++) {
      dest.coeffs[i] = ModQ.reduceBarrett(a.coeffs[i], params);
    }
  }

  static Poly add(Poly a, Poly b) {
    final dest = Poly.zero(a.ring);
    addInto(dest, a, b);
    return dest;
  }

  static Poly sub(Poly a, Poly b) {
    final dest = Poly.zero(a.ring);
    subInto(dest, a, b);
    return dest;
  }

  static void _sameRing(Poly dest, Poly a, Poly b) {
    if (dest.n != a.n || dest.n != b.n || dest.q != a.q || dest.q != b.q) {
      throw ArgumentError('ring mismatch');
    }
  }
}
