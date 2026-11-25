import 'dart:typed_data';

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
/// loads or `%` fallback. Packed `Int16List` / `Int32List` operands take a
/// callee whose parameters are that concrete type. A `List<int>` parameter
/// stays an interface call under AOT and measured several times slower on
/// the same recipe (`doc/SIMD.md` §2). A plain [List] falls back to the
/// same recipe.
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

  /// Pair-basemul twiddles in `int16` lanes. Values are the FIPS 203 gammas,
  /// all in `[0, q)`, so the narrowing copy is exact.
  static final Int16List _mlKemGammasI16 = Int16List.fromList(mlKemGammas);

  static _MontGammaCache? _mlKemGammaMont;

  /// Montgomery-form ML-KEM gammas for [params], built once per constant set.
  static Int16List _mlKemGammasMont(MontgomeryParams params) {
    final cached = _mlKemGammaMont;
    if (cached != null &&
        cached.q == params.q &&
        cached.nPrime == params.nPrime &&
        cached.r2 == params.r2 &&
        cached.logR == params.logR) {
      return cached.lanes;
    }
    final lanes = Int16List(mlKemGammas.length);
    for (var i = 0; i < lanes.length; i++) {
      lanes[i] = ModQ.toMont(mlKemGammas[i], params);
    }
    _mlKemGammaMont = _MontGammaCache(
      params.q,
      params.nPrime,
      params.r2,
      params.logR,
      lanes,
    );
    return lanes;
  }

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
      if (d is Int16List && a is Int16List && b is Int16List) {
        _pointwiseMlKem(d, a, b);
        return;
      }
      for (var i = 0; i < n; i++) {
        d[i] = mlKemMulBarrett(a[i], b[i]);
      }
      return;
    }
    if (q == 12289 && (n == 512 || n == 1024)) {
      if (d is Int16List && a is Int16List && b is Int16List) {
        _pointwiseFnDsa(d, a, b);
        return;
      }
      for (var i = 0; i < n; i++) {
        d[i] = fnDsaReduceK27(a[i] * b[i]);
      }
      return;
    }
    if (q == 8380417 && n == 256) {
      // Plain-domain product via two 32-bit-word REDCs:
      // REDC(a·b) = a·b·R⁻¹; REDC((a·b·R⁻¹)·R²) = a·b. Both products stay
      // below q² < 2^46, so the single 64-bit-limb REDC bound holds.
      if (d is Int32List && a is Int32List && b is Int32List) {
        _pointwiseMlDsa(d, a, b);
        return;
      }
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
    final q = ring.q;
    final n = ring.n;
    final a = aHat.coeffs;
    final b = bHat.coeffs;
    final d = dest.coeffs;
    if (q == 3329 && d is Int16List && a is Int16List && b is Int16List) {
      for (var i = 0; i < n; i++) {
        d[i] = montMulR16(a[i], b[i], q, 3327);
      }
      return;
    }
    if (q == 12289 && d is Int16List && a is Int16List && b is Int16List) {
      for (var i = 0; i < n; i++) {
        d[i] = montMulR16(a[i], b[i], q, 12287);
      }
      return;
    }
    if (q == 8380417 && d is Int32List && a is Int32List && b is Int32List) {
      for (var i = 0; i < n; i++) {
        d[i] = mlDsaRedc(a[i] * b[i]);
      }
      return;
    }
    for (var i = 0; i < n; i++) {
      d[i] = ModQ.montMul(a[i], b[i], params);
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
    if (d is Int16List && a is Int16List && b is Int16List) {
      _mlKemPairsI16(d, a, b);
      return;
    }
    for (var i = 0; i < 256; i += 2) {
      final a0 = a[i];
      final a1 = a[i + 1];
      final b0 = b[i];
      final b1 = b[i + 1];
      final gamma = gammas[i >> 1];
      final t0 = mlKemMulBarrett(a0, b0);
      final t1 = mlKemMulBarrett(mlKemMulBarrett(a1, b1), gamma);
      final s0 = t0 + t1;
      d[i] = maskCsub(s0, q);
      final s1 = mlKemMulBarrett(a0, b1) + mlKemMulBarrett(a1, b0);
      d[i + 1] = maskCsub(s1, q);
    }
  }

  /// ML-KEM pair basemul in Montgomery domain.
  ///
  /// [aHat], [bHat], and [dest] must hold Montgomery-domain values (output of
  /// an NTT run with the same [MontgomeryParams]). Gammas are converted once
  /// per parameter set and reused. The result stays in the Montgomery domain
  /// and matches [mlKemPairsInPlace] after `fromMont` on the plain path.
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
    final gammas = _mlKemGammasMont(params);
    final a = aHat.coeffs;
    final b = bHat.coeffs;
    final d = dest.coeffs;
    if (d is Int16List && a is Int16List && b is Int16List) {
      _mlKemPairsMontI16(d, a, b, gammas);
      return;
    }
    const q = 3329;
    for (var i = 0; i < 256; i += 2) {
      final a0 = a[i];
      final a1 = a[i + 1];
      final b0 = b[i];
      final b1 = b[i + 1];
      final gamma = gammas[i >> 1];
      final t0 = montMulR16(a0, b0, q, 3327);
      final t1 = montMulR16(montMulR16(a1, b1, q, 3327), gamma, q, 3327);
      final s0 = t0 + t1;
      d[i] = s0 - (q & ~((s0 - q) >> 63));
      final s1 = montMulR16(a0, b1, q, 3327) + montMulR16(a1, b0, q, 3327);
      d[i + 1] = s1 - (q & ~((s1 - q) >> 63));
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

  static void _pointwiseMlKem(Int16List d, Int16List a, Int16List b) {
    for (var i = 0; i < 256; i++) {
      d[i] = mlKemMulBarrett(a[i], b[i]);
    }
  }

  static void _pointwiseFnDsa(Int16List d, Int16List a, Int16List b) {
    final n = d.length;
    for (var i = 0; i < n; i++) {
      d[i] = fnDsaReduceK27(a[i] * b[i]);
    }
  }

  /// Two REDCs, plain residue. [a] and [b] are in `[0, q)`.
  static void _pointwiseMlDsa(Int32List d, Int32List a, Int32List b) {
    for (var i = 0; i < 256; i++) {
      final t = mlDsaRedc(a[i] * b[i]);
      d[i] = mlDsaRedc(t * _mlDsaR2);
    }
  }

  static void _mlKemPairsI16(Int16List d, Int16List a, Int16List b) {
    const q = 3329;
    final gammas = _mlKemGammasI16;
    for (var i = 0; i < 256; i += 2) {
      final a0 = a[i];
      final a1 = a[i + 1];
      final b0 = b[i];
      final b1 = b[i + 1];
      final gamma = gammas[i >> 1];
      final t0 = mlKemMulBarrett(a0, b0);
      final t1 = mlKemMulBarrett(mlKemMulBarrett(a1, b1), gamma);
      final s0 = t0 + t1;
      d[i] = maskCsub(s0, q);
      final s1 = mlKemMulBarrett(a0, b1) + mlKemMulBarrett(a1, b0);
      d[i + 1] = maskCsub(s1, q);
    }
  }

  static void _mlKemPairsMontI16(
    Int16List d,
    Int16List a,
    Int16List b,
    Int16List gammas,
  ) {
    const q = 3329;
    const nPrime = 3327;
    for (var i = 0; i < 256; i += 2) {
      final a0 = a[i];
      final a1 = a[i + 1];
      final b0 = b[i];
      final b1 = b[i + 1];
      final gamma = gammas[i >> 1];
      final t0 = montMulR16(a0, b0, q, nPrime);
      final t1 = montMulR16(montMulR16(a1, b1, q, nPrime), gamma, q, nPrime);
      final s0 = t0 + t1;
      d[i] = s0 - (q & ~((s0 - q) >> 63));
      final s1 = montMulR16(a0, b1, q, nPrime) + montMulR16(a1, b0, q, nPrime);
      d[i + 1] = s1 - (q & ~((s1 - q) >> 63));
    }
  }
}

final class _MontGammaCache {
  final int q;
  final int nPrime;
  final int r2;
  final int logR;
  final Int16List lanes;

  const _MontGammaCache(this.q, this.nPrime, this.r2, this.logR, this.lanes);
}
