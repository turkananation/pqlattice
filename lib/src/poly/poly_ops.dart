import 'dart:typed_data';

import '../mod/mod_q.dart';
import '../ntt/ntt_reduce.dart';
import '../mod/barrett_params.dart';
import 'poly.dart';

/// Coefficient-wise operations (no NTT).
///
/// Packed `Int16List` / `Int32List` buffers take a monomorphic loop. Add, sub,
/// and neg use one mask correction and require coefficients already in
/// `[0, q)`, which is what NTT and basemul produce. A plain [List] still uses
/// [ModQ.add] / [ModQ.sub], so an unreduced caller list is fully reduced.
/// [reduceInto] is the operation that accepts arbitrary integers.
final class PolyOps {
  PolyOps._();

  static const int _mlDsaR2 = 2365951;

  static void addInto(Poly dest, Poly a, Poly b) {
    _sameRing(dest, a, b);
    final q = dest.q;
    final d = dest.coeffs;
    final x = a.coeffs;
    final y = b.coeffs;
    if (d is Int16List && x is Int16List && y is Int16List) {
      _add16(d, x, y, q);
      return;
    }
    if (d is Int32List && x is Int32List && y is Int32List) {
      _add32(d, x, y, q);
      return;
    }
    for (var i = 0; i < d.length; i++) {
      d[i] = ModQ.add(x[i], y[i], q);
    }
  }

  static void subInto(Poly dest, Poly a, Poly b) {
    _sameRing(dest, a, b);
    final q = dest.q;
    final d = dest.coeffs;
    final x = a.coeffs;
    final y = b.coeffs;
    if (d is Int16List && x is Int16List && y is Int16List) {
      _sub16(d, x, y, q);
      return;
    }
    if (d is Int32List && x is Int32List && y is Int32List) {
      _sub32(d, x, y, q);
      return;
    }
    for (var i = 0; i < d.length; i++) {
      d[i] = ModQ.sub(x[i], y[i], q);
    }
  }

  static void negInto(Poly dest, Poly a) {
    if (dest.n != a.n || dest.q != a.q) {
      throw ArgumentError('ring mismatch');
    }
    final q = dest.q;
    final d = dest.coeffs;
    final x = a.coeffs;
    if (d is Int16List && x is Int16List) {
      for (var i = 0; i < d.length; i++) {
        d[i] = _subq(0, x[i], q);
      }
      return;
    }
    if (d is Int32List && x is Int32List) {
      for (var i = 0; i < d.length; i++) {
        d[i] = _subq(0, x[i], q);
      }
      return;
    }
    for (var i = 0; i < d.length; i++) {
      d[i] = ModQ.sub(0, x[i], q);
    }
  }

  /// Reduce every coefficient into \([0, q)\) via [ModQ.reduce].
  ///
  /// This is the general reduction. It divides. Add, sub, and neg do not.
  static void reduceInto(Poly dest, Poly a) {
    if (dest.n != a.n || dest.q != a.q) {
      throw ArgumentError('ring mismatch');
    }
    final q = dest.q;
    final d = dest.coeffs;
    final x = a.coeffs;
    if (d is Int16List && x is Int16List) {
      for (var i = 0; i < d.length; i++) {
        d[i] = ModQ.reduce(x[i], q);
      }
      return;
    }
    if (d is Int32List && x is Int32List) {
      for (var i = 0; i < d.length; i++) {
        d[i] = ModQ.reduce(x[i], q);
      }
      return;
    }
    for (var i = 0; i < d.length; i++) {
      d[i] = ModQ.reduce(x[i], q);
    }
  }

  /// Scale: \(dest_i = (k \cdot a_i) \bmod q\).
  ///
  /// Packed lanes use the profile product (ML-KEM Barrett, FN-DSA k=27,
  /// ML-DSA double REDC). [k] is reduced once. Each `a_i` must already be in
  /// `[0, q)`. A plain [List] uses [ModQ.mul], which accepts unreduced inputs.
  static void scaleInto(Poly dest, Poly a, int k) {
    if (dest.n != a.n || dest.q != a.q) {
      throw ArgumentError('ring mismatch');
    }
    final q = dest.q;
    final d = dest.coeffs;
    final x = a.coeffs;
    final k0 = ModQ.reduce(k, q);
    if (d is Int16List && x is Int16List && q == 3329) {
      for (var i = 0; i < d.length; i++) {
        d[i] = mlKemMulBarrett(x[i], k0);
      }
      return;
    }
    if (d is Int16List && x is Int16List && q == 12289) {
      for (var i = 0; i < d.length; i++) {
        d[i] = fnDsaReduceK27(x[i] * k0);
      }
      return;
    }
    if (d is Int32List && x is Int32List && q == 8380417) {
      for (var i = 0; i < d.length; i++) {
        final t = mlDsaRedc(x[i] * k0);
        d[i] = mlDsaRedc(t * _mlDsaR2);
      }
      return;
    }
    for (var i = 0; i < d.length; i++) {
      d[i] = ModQ.mul(x[i], k, q);
    }
  }

  /// Barrett-reduce every coefficient when params are ready.
  static void reduceBarrettInto(Poly dest, Poly a, BarrettParams params) {
    if (dest.n != a.n || dest.q != a.q || dest.q != params.q) {
      throw ArgumentError('ring / params mismatch');
    }
    final d = dest.coeffs;
    final x = a.coeffs;
    if (d is Int16List && x is Int16List) {
      for (var i = 0; i < d.length; i++) {
        d[i] = ModQ.reduceBarrett(x[i], params);
      }
      return;
    }
    if (d is Int32List && x is Int32List) {
      for (var i = 0; i < d.length; i++) {
        d[i] = ModQ.reduceBarrett(x[i], params);
      }
      return;
    }
    for (var i = 0; i < d.length; i++) {
      d[i] = ModQ.reduceBarrett(x[i], params);
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

  static void _add16(Int16List d, Int16List a, Int16List b, int q) {
    for (var i = 0; i < d.length; i++) {
      d[i] = _addq(a[i], b[i], q);
    }
  }

  static void _add32(Int32List d, Int32List a, Int32List b, int q) {
    for (var i = 0; i < d.length; i++) {
      d[i] = _addq(a[i], b[i], q);
    }
  }

  static void _sub16(Int16List d, Int16List a, Int16List b, int q) {
    for (var i = 0; i < d.length; i++) {
      d[i] = _subq(a[i], b[i], q);
    }
  }

  static void _sub32(Int32List d, Int32List a, Int32List b, int q) {
    for (var i = 0; i < d.length; i++) {
      d[i] = _subq(a[i], b[i], q);
    }
  }

  static int _addq(int a, int b, int q) {
    final sum = a + b;
    final sn = sum - q;
    return sum - (q & ~(sn >> 63));
  }

  static int _subq(int a, int b, int q) {
    final d = a - b;
    return d + (q & (d >> 63));
  }

  static void _sameRing(Poly dest, Poly a, Poly b) {
    if (dest.n != a.n || dest.n != b.n || dest.q != a.q || dest.q != b.q) {
      throw ArgumentError('ring mismatch');
    }
  }
}
