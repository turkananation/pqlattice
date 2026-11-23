import 'dart:typed_data';

import 'ntt_reduce.dart';

/// Scalar NTT kernels over a coefficient buffer.
///
/// These run the **same reduction recipes** as the `Int32x4` kernels in
/// `ntt_simd_int32x4.dart`, imported from `ntt_reduce.dart` so a rewrite cannot
/// drift from the certified residue function.
///
/// **Buffer types.** The parameter is `Int32List`, and the engine always calls
/// these kernels on `NttWorkspace.lanes` after a typed staging copy. Both the
/// concrete lane type and the typed copy matter: the same loop over an
/// interface-typed `Poly.coeffs` buffer measured ~3× slower at engine level
/// (ML-KEM forward). Staging is part of the accelerated design, not an
/// optional copy (`doc/SIMD.md` §4).
///
/// This tier is the comparator and fallback for the `Int32x4` kernels; its
/// speed comes from typed lanes, not from vectorization.
///
/// Results are bit-identical to the `Int32x4` kernels by construction: every
/// stage canonicalizes into `[0, q)`, and the widest intermediate in one
/// butterfly is `< 2q`.
final class NttScalar {
  NttScalar._();

  // ── ML-KEM (q = 3329, n = 256) ───────────────────────────────────────────

  /// ML-KEM forward, `q = 3329`, `n = 256`, Barrett butterfly.
  static void mlKemForward(Int32List f, List<int> zetas) {
    const q = 3329;
    var k = 1;
    for (var len = 128; len >= 2; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final fj = f[j];
          final t = mlKemMulBarrett(zeta, f[j + len]);
          final diff = fj - t;
          f[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          f[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// ML-KEM inverse, `q = 3329`, `n = 256`.
  static void mlKemInverse(Int32List f, List<int> zetas, int invScale) {
    const q = 3329;
    var k = 127;
    for (var len = 2; len <= 128; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k--];
        for (var j = start; j < start + len; j++) {
          final fj = f[j];
          final fjl = f[j + len];
          final sum = fj + fjl;
          f[j] = sum >= q ? sum - q : sum;
          final diff = fjl - fj;
          final reducedDiff = diff < 0 ? diff + q : diff;
          f[j + len] = mlKemMulBarrett(zeta, reducedDiff);
        }
      }
    }
    for (var i = 0; i < 256; i++) {
      f[i] = mlKemMulBarrett(f[i], invScale);
    }
  }

  /// ML-DSA forward, `q = 8380417`, `n = 256`, Montgomery REDC butterflies.
  ///
  /// [zetasMont] are the Montgomery-form twiddles (`zeta * R mod q`) so the
  /// polynomial stays in the plain domain throughout: `REDC(zetaM · x) ≡
  /// zeta · x`.
  static void mlDsaForward(Int32List a, List<int> zetasMont) {
    const q = 8380417;
    var k = 1;
    for (var len = 128; len >= 1; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zetaM = zetasMont[k++];
        for (var j = start; j < start + len; j++) {
          final t = mlDsaRedc(zetaM * a[j + len]);
          final fj = a[j];
          final diff = fj - t;
          a[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          a[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// ML-DSA inverse, `q = 8380417`, `n = 256`.
  static void mlDsaInverse(Int32List a, List<int> zetasMont, int invMont) {
    const q = 8380417;
    var ik = 255;
    for (var len = 1; len < 256; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        var zetaM = zetasMont[ik--];
        zetaM = q - zetaM; // -zeta in Montgomery form
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          final sum = t + u;
          a[j] = sum >= q ? sum - q : sum;
          final diff = t - u;
          final d = diff < 0 ? diff + q : diff;
          a[j + len] = mlDsaRedc(zetaM * d);
        }
      }
    }
    for (var i = 0; i < 256; i++) {
      a[i] = mlDsaRedc(invMont * a[i]);
    }
  }

  /// FN-DSA forward, `q = 12289`, `n ∈ {512, 1024}`, k = 27 Barrett.
  static void fnDsaForward(Int32List a, int n, List<int> zetas) {
    const q = 12289;
    var k = 1;
    for (var len = n >> 1; len >= 1; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final t = fnDsaReduceK27(zeta * a[j + len]);
          final fj = a[j];
          final diff = fj - t;
          a[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          a[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// FN-DSA inverse, `q = 12289`, `n ∈ {512, 1024}`, conjugate twiddles.
  static void fnDsaInverse(
    Int32List a,
    int n,
    List<int> zetas,
    int invScale,
  ) {
    const q = 12289;
    var ik = n - 1;
    for (var len = 1; len < n; len <<= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = q - zetas[ik--]; // -zeta mod q
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          final sum = t + u;
          a[j] = sum >= q ? sum - q : sum;
          final diff = t - u;
          final d = diff < 0 ? diff + q : diff;
          a[j + len] = fnDsaReduceK27(d * zeta);
        }
      }
    }
    for (var i = 0; i < n; i++) {
      a[i] = fnDsaReduceK27(a[i] * invScale);
    }
  }
}
