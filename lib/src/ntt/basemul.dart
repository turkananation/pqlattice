import '../mod/barrett_params.dart';
import '../mod/mod_q.dart';
import '../mod/montgomery_params.dart';
import '../poly/poly.dart';
import '../ring/ring_params.dart';
import 'mlkem_tables.dart';
import 'ntt_params.dart';
import 'ntt_reduce.dart';

/// NTT-domain products — accelerated mul-reduce by default.
///
/// The hot loops are dispatched per ring so each runs one monomorphic typed
/// loop with an **inlined** reduction recipe and no `BarrettParams` object
/// loads or `%` fallback:
///
/// | Ring | Recipe | Provenance |
/// | ---- | ------ | ---------- |
/// | ML-KEM `q=3329` | [mlKemMulBarrett] | exhaustive over 3329² products |
/// | FN-DSA `q=12289` | [fnDsaReduceK27] | exhaustive over 12289² products |
/// | ML-DSA `q=8380417` | two 32-bit-word REDCs | `REDC(REDC(a·b)·R²) = a·b` |
///
/// Results are canonical residues, bit-identical to the previous
/// `ModQ.reduceBarrett` / `%` path.
final class Basemul {
  Basemul._();

  /// `R² mod q` for ML-DSA (`R = 2^32`), mirroring
  /// [MontgomeryParams.forQ]`(8380417).r2`.
  static const int _mlDsaR2 = 2365951;

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
    final q = ring.q;
    final n = ring.n;
    final a = aHat.coeffs;
    final b = bHat.coeffs;
    final d = dest.coeffs;

    if (q == 3329 && n == 256) {
      for (var i = 0; i < n; i++) {
        d[i] = mlKemMulBarrett(a[i], b[i]);
      }
      return;
    }
    if (q == 12289 && (n == 512 || n == 1024)) {
      for (var i = 0; i < n; i++) {
        d[i] = fnDsaReduceK27(a[i] * b[i]);
      }
      return;
    }
    if (q == 8380417 && n == 256) {
      // Plain-domain product via two 32-bit-word REDCs:
      // REDC(a·b) = a·b·R⁻¹; REDC((a·b·R⁻¹)·R²) = a·b. Both products stay
      // below q² < 2^46, so the single 64-bit-limb REDC bound holds.
      for (var i = 0; i < n; i++) {
        final t = mlDsaRedc(a[i] * b[i]);
        d[i] = mlDsaRedc(t * _mlDsaR2);
      }
      return;
    }
    final barrett = BarrettParams.forQ(q);
    for (var i = 0; i < n; i++) {
      final prod = a[i] * b[i];
      d[i] = barrett.isReady
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
    const q = 3329;
    final gammas = mlKemGammas;
    final a = aHat.coeffs;
    final b = bHat.coeffs;
    final d = dest.coeffs;
    for (var i = 0; i < 256; i += 2) {
      final a0 = a[i];
      final a1 = a[i + 1];
      final b0 = b[i];
      final b1 = b[i + 1];
      final gamma = gammas[i >> 1];
      final t0 = mlKemMulBarrett(a0, b0);
      final t1 = mlKemMulBarrett(mlKemMulBarrett(a1, b1), gamma);
      final s0 = t0 + t1;
      d[i] = s0 >= q ? s0 - q : s0;
      final s1 = mlKemMulBarrett(a0, b1) + mlKemMulBarrett(a1, b0);
      d[i + 1] = s1 >= q ? s1 - q : s1;
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
