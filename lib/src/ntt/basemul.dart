import '../mod/barrett_params.dart';
import '../mod/mod_q.dart';
import '../mod/montgomery_params.dart';
import '../poly/poly.dart';
import '../ring/ring_params.dart';
import 'mlkem_tables.dart';
import 'ntt_params.dart';

/// NTT-domain products — accelerated mul-reduce by default.
final class Basemul {
  Basemul._();

  static Poly pointwise(Poly aHat, Poly bHat, RingParams ring) {
    if (aHat.n != ring.n || bHat.n != ring.n) {
      throw ArgumentError('length mismatch');
    }
    final out = Poly.zero(ring);
    pointwiseInPlace(out, aHat, bHat, ring);
    return out;
  }

  static void pointwiseInPlace(
    Poly dest,
    Poly aHat,
    Poly bHat,
    RingParams ring,
  ) {
    if (dest.n != ring.n || aHat.n != ring.n || bHat.n != ring.n) {
      throw ArgumentError('length mismatch');
    }
    final barrett = BarrettParams.forQ(ring.q);
    final q = ring.q;
    for (var i = 0; i < ring.n; i++) {
      final prod = aHat.coeffs[i] * bHat.coeffs[i];
      dest.coeffs[i] = barrett.isReady
          ? ModQ.reduceBarrett(prod, barrett)
          : ModQ.reduce(prod, q);
    }
  }

  /// Pointwise product in Montgomery domain.
  ///
  /// [aHat] and [bHat] must be Montgomery-domain values (output of an NTT run
  /// with Montgomery params). Result is in Montgomery domain. Use with
  /// [NttEngine] constructed with the same [MontgomeryParams]; results are
  /// bit-identical to [pointwiseInPlace] on the Barrett/%-path.
  static void pointwiseMontgomeryInPlace(
    Poly dest,
    Poly aHat,
    Poly bHat,
    RingParams ring,
    MontgomeryParams params,
  ) {
    if (dest.n != ring.n || aHat.n != ring.n || bHat.n != ring.n) {
      throw ArgumentError('length mismatch');
    }
    if (!params.isReady) {
      throw StateError('MontgomeryParams are not ready for q=${params.q}');
    }
    if (ring.q != params.q) {
      throw ArgumentError(
        'ring q=${ring.q} does not match MontgomeryParams q=${params.q}',
      );
    }
    for (var i = 0; i < ring.n; i++) {
      dest.coeffs[i] = ModQ.montMul(aHat.coeffs[i], bHat.coeffs[i], params);
    }
  }

  static Poly pointwiseMontgomery(
    Poly aHat,
    Poly bHat,
    RingParams ring,
    MontgomeryParams params,
  ) {
    if (aHat.n != ring.n || bHat.n != ring.n) {
      throw ArgumentError('length mismatch');
    }
    final out = Poly.zero(ring);
    pointwiseMontgomeryInPlace(out, aHat, bHat, ring, params);
    return out;
  }

  /// FIPS 203 pair basemul (pqcrypto `Poly.baseMul`).
  static Poly mlKemPairs(Poly aHat, Poly bHat, RingParams ring) {
    if (ring.q != 3329 || ring.n != 256) {
      throw ArgumentError('mlKemPairs expects ML-KEM ring (q=3329, n=256)');
    }
    final out = Poly.zero(ring);
    mlKemPairsInPlace(out, aHat, bHat);
    return out;
  }

  static void mlKemPairsInPlace(Poly dest, Poly aHat, Poly bHat) {
    if (dest.n != 256 || aHat.n != 256 || bHat.n != 256) {
      throw ArgumentError('length mismatch');
    }
    final barrett = BarrettParams.mlKem;
    final q = 3329;
    final gammas = mlKemGammas;
    for (var i = 0; i < 256; i += 2) {
      final a0 = aHat.coeffs[i];
      final a1 = aHat.coeffs[i + 1];
      final b0 = bHat.coeffs[i];
      final b1 = bHat.coeffs[i + 1];
      final gamma = gammas[i >> 1];
      final t0 = ModQ.mulBarrett(a0, b0, barrett);
      final t1 = ModQ.mulBarrett(
        ModQ.mulBarrett(a1, b1, barrett),
        gamma,
        barrett,
      );
      dest.coeffs[i] = ModQ.addFast(t0, t1, q);
      dest.coeffs[i + 1] = ModQ.addFast(
        ModQ.mulBarrett(a0, b1, barrett),
        ModQ.mulBarrett(a1, b0, barrett),
        q,
      );
    }
  }

  /// ML-KEM pair basemul in Montgomery domain.
  ///
  /// [aHat], [bHat], and [dest] must hold Montgomery-domain values (output of
  /// an NTT run with Montgomery params). [gammas] are converted to Montgomery
  // domain on the fly. Result is in Montgomery domain. Results are bit-
  // identical to [mlKemPairsInPlace] on the Barrett/%-path.
  static void mlKemPairsMontgomeryInPlace(
    Poly dest,
    Poly aHat,
    Poly bHat,
    MontgomeryParams params,
  ) {
    if (dest.n != 256 || aHat.n != 256 || bHat.n != 256) {
      throw ArgumentError('length mismatch');
    }
    if (!params.isReady) {
      throw StateError('MontgomeryParams are not ready for q=${params.q}');
    }
    if (params.q != 3329) {
      throw ArgumentError(
        'mlKemPairsMontgomery expects ML-KEM ring (q=3329), got q=${params.q}',
      );
    }
    final q = 3329;
    final gammas = mlKemGammas;
    for (var i = 0; i < 256; i += 2) {
      final a0 = aHat.coeffs[i];
      final a1 = aHat.coeffs[i + 1];
      final b0 = bHat.coeffs[i];
      final b1 = bHat.coeffs[i + 1];
      final gamma = ModQ.toMont(gammas[i >> 1], params);
      final t0 = ModQ.montMul(a0, b0, params);
      final t1 = ModQ.montMul(ModQ.montMul(a1, b1, params), gamma, params);
      dest.coeffs[i] = ModQ.addFast(t0, t1, q);
      dest.coeffs[i + 1] = ModQ.addFast(
        ModQ.montMul(a0, b1, params),
        ModQ.montMul(a1, b0, params),
        q,
      );
    }
  }

  static Poly mlKemPairsMontgomery(
    Poly aHat,
    Poly bHat,
    MontgomeryParams params,
  ) {
    if (aHat.n != 256 || bHat.n != 256) {
      throw ArgumentError('length mismatch');
    }
    final out = Poly.zero(RingParams.mlKem);
    mlKemPairsMontgomeryInPlace(out, aHat, bHat, params);
    return out;
  }

  static Poly mlKemPairsWithParams(Poly aHat, Poly bHat, NttParams params) {
    if (params.gammas.length != 128) {
      throw StateError('ML-KEM gammas missing on NttParams');
    }
    return mlKemPairs(aHat, bHat, params.ring);
  }
}
