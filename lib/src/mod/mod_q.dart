import 'barrett_params.dart';
import 'montgomery_params.dart';

/// Modular arithmetic in \(\mathbb{Z}_q\).
///
/// **Hot path (accelerated default):** [addFast], [subFast], [mulBarrett],
/// [reduceBarrett], and Montgomery helpers when parameters are ready.
///
/// **Oracle path:** [reduce], [add], [sub], [mul] using remainder with a
/// non-negative representative in \([0, q)\).
///
/// [addFast] / [subFast] assume inputs are already reduced into a range where
/// a single conditional correction suffices (typically both in \([0, q)\)).
/// They are intended for NTT butterflies after prior reduction discipline.
///
/// See `doc/REDUCTION.md` and `doc/INTEROP_AND_FIPS_RULE.md`.
final class ModQ {
  ModQ._();

  /// Non-negative residue of [a] modulo [q] in \([0, q)\).
  static int reduce(int a, int q) {
    if (q <= 0) {
      throw ArgumentError.value(q, 'q', 'modulus must be positive');
    }
    var r = a % q;
    if (r < 0) r += q;
    return r;
  }

  /// \((a + b) \bmod q\) via [reduce].
  static int add(int a, int b, int q) => reduce(a + b, q);

  /// \((a - b) \bmod q\) via [reduce].
  static int sub(int a, int b, int q) => reduce(a - b, q);

  /// \((a \cdot b) \bmod q\) via [reduce].
  static int mul(int a, int b, int q) => reduce(a * b, q);

  /// Single conditional add for values already near \([0, q)\).
  static int addFast(int a, int b, int q) {
    final x = a + b;
    return x >= q ? x - q : x;
  }

  /// Single conditional sub for values already near \([0, q)\).
  static int subFast(int a, int b, int q) {
    final x = a - b;
    return x < 0 ? x + q : x;
  }

  /// Product reduced with Barrett parameters (falls back to [reduce] if not ready).
  static int mulBarrett(int a, int b, BarrettParams params) =>
      reduceBarrett(a * b, params);

  /// Centered representative of [a] mod [q] in \((-\lfloor q/2\rfloor, \lfloor q/2\rfloor]\).
  static int center(int a, int q) {
    final r = reduce(a, q);
    return r > (q >> 1) ? r - q : r;
  }

  /// Alias for [reduce] (canonical non-negative residue).
  static int freeze(int a, int q) => reduce(a, q);

  /// Subtract [q] if [a] `>=` [q]; otherwise return [a]. Does not handle negatives.
  static int csubq(int a, int q) => a >= q ? a - q : a;

  /// Barrett reduction of [a] into \([0, q)\).
  ///
  /// If [BarrettParams.isReady] is false, or [a] is negative, uses [reduce].
  /// Positive inputs use the multiply-shift approximation and a fixed number
  /// of [csubq] corrections; a final adjustment handles residual negatives.
  static int reduceBarrett(int a, BarrettParams params) {
    if (!params.isReady) return reduce(a, params.q);
    if (a < 0) return reduce(a, params.q);
    final q = params.q;
    final quotient = (a * params.mu) >> params.shift;
    var r = a - quotient * q;
    r = csubq(r, q);
    r = csubq(r, q);
    r = csubq(r, q);
    if (r < 0) r += q;
    // Defensive: pathological oversized inputs still converge via `%`.
    if (r >= q) return reduce(r, q);
    return r;
  }

  /// Montgomery reduction: returns \(a \cdot R^{-1} \bmod q\) in \([0, q)\).
  ///
  /// Requires [MontgomeryParams.isReady]. Input bound: \(0 \le a < q \cdot R\).
  /// Values outside this bound (including negatives) are rejected — Montgomery
  /// reduction is not defined for them and silently returning a wrong residue
  /// would break interop.
  ///
  /// Edge cases handled:
  /// - [a] = 0 → returns 0
  /// - [a] = q·R − 1 (max valid input) → reduces correctly
  /// - [a] = q − 1 → returns (q−1)·R⁻¹ mod q
  static int montReduce(int a, MontgomeryParams params) {
    if (!params.isReady) {
      throw StateError('MontgomeryParams are not ready for q=${params.q}');
    }
    if (a < 0) {
      throw ArgumentError.value(
        a,
        'a',
        'montReduce requires 0 <= a < q*R; negative input is outside the Montgomery domain',
      );
    }
    final q = params.q;
    final r = params.r;
    final bound = q * r;
    if (a >= bound) {
      throw ArgumentError.value(
        a,
        'a',
        'montReduce requires 0 <= a < q*R; got $a, bound $bound',
      );
    }
    final mask = params.rMask;
    final logR = params.logR;
    final t = ((a & mask) * params.nPrime) & mask;
    var u = (a + t * q) >> logR;
    if (u >= q) u -= q;
    if (u < 0) u += q;
    return u;
  }

  /// Product in Montgomery domain: \(a_{\mathrm{m}} b_{\mathrm{m}} R^{-1} \bmod q\).
  ///
  /// Both [a] and [b] must be Montgomery-domain values in \([0, q)\).
  /// Result is in \([0, q)\) and in Montgomery domain.
  static int montMul(int a, int b, MontgomeryParams params) {
    if (!params.isReady) {
      throw StateError('MontgomeryParams are not ready for q=${params.q}');
    }
    if (a < 0 || a >= params.q) {
      throw ArgumentError.value(
        a,
        'a',
        'montMul requires Montgomery-domain operand in [0, q)',
      );
    }
    if (b < 0 || b >= params.q) {
      throw ArgumentError.value(
        b,
        'b',
        'montMul requires Montgomery-domain operand in [0, q)',
      );
    }
    return montReduce(a * b, params);
  }

  /// Maps [a] into the Montgomery domain: \(a R \bmod q\).
  ///
  /// Accepts any integer [a]; reduces to \([0, q)\) first, then converts.
  /// Result is in \([0, q)\) and in Montgomery domain.
  static int toMont(int a, MontgomeryParams params) {
    if (!params.isReady) {
      throw StateError('MontgomeryParams are not ready for q=${params.q}');
    }
    return montReduce(reduce(a, params.q) * params.r2, params);
  }

  /// Maps a Montgomery value back to a plain residue: \(a_{\mathrm{m}} R^{-1} \bmod q\).
  ///
  /// [a] must be a Montgomery-domain value in \([0, q)\).
  /// Result is in \([0, q)\) in the normal (non-Montgomery) domain.
  static int fromMont(int a, MontgomeryParams params) {
    if (!params.isReady) {
      throw StateError('MontgomeryParams are not ready for q=${params.q}');
    }
    if (a < 0 || a >= params.q) {
      throw ArgumentError.value(
        a,
        'a',
        'fromMont requires Montgomery-domain operand in [0, q)',
      );
    }
    return montReduce(a, params);
  }
}
