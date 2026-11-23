import 'dart:typed_data';

import '../ntt/ntt_reduce.dart';
import 'ntt_workspace.dart';

/// Two-pass `Int32x4` NTT kernels.
///
/// Each stage splits into
///
/// 1. a **scalar multiply-reduce pass** over the stage's high half, using the
///    exact per-profile recipe from `ntt_reduce.dart`, and
/// 2. a **4-lane combine pass** that does only `add`, `sub`, and branchless
///    canonicalization `d + ((d >> 31) & q)`.
///
/// No new algebra is introduced. For inputs `lo, hi ∈ [0, q)` the combine
/// intermediates satisfy `lo + hi ∈ [0, 2q)` and `lo - hi ∈ (-q, q)`, so a
/// single conditional subtraction is exact; `d + ((d >> 31) & q)` is bit-equal
/// to `d < 0 ? d + q : d` over that interval. Results are therefore
/// **bit-identical** to the typed scalar kernels by construction, not by
/// sampling — verified per profile in `test/simd_ntt_parity_test.dart`.
///
/// Twiddle indexing is **per block**, not per stage: every `start` block in a
/// stage consumes its own zeta (forward `k++`, inverse `k--`), exactly as the
/// scalar butterflies do. Hoisting `zetas[k++]` out of the block loop is a
/// correctness bug, not an optimization.
///
/// Stage selection: only stages with `len >= 4` have whole 16-byte groups
/// (`len >> 2 >= 1`), so `len ∈ {1, 2}` stays scalar. Every `start` is a
/// multiple of `2·len ≥ 8`, so its `int32` byte offset is a multiple of 16.
///
/// Backend: real vector registers on the Dart VM (engine-level 1.5×–2.3×
/// depending on ring and direction) and on dart2wasm (`v128`, unmeasured);
/// dart2js emulation measured 0.50× and is excluded in `SimdCapability`.
/// All four shipped profiles clear the 1.5× adoption bar at engine level —
/// see `LatticeKernels.preferSimdNtt`.
final class NttSimdInt32x4 {
  NttSimdInt32x4._();

  // ── ML-KEM (q = 3329, n = 256) ───────────────────────────────────────────

  /// ML-KEM forward: Barrett multiply pass + vector combine.
  static void mlKemForward(NttWorkspace ws, List<int> zetas) {
    const q = 3329;
    const n = 256;
    final f = ws.lanes;
    final v = ws.vectors;
    final qv = Int32x4(q, q, q, q);
    var k = 1;

    var len = 128;
    for (; len >= 4; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k++];
        final hi = start + len;
        for (var j = 0; j < len; j++) {
          f[hi + j] = mlKemMulBarrett(zeta, f[hi + j]);
        }
      }
      _forwardCombine(v, n, len, qv);
    }
    // len = 2: the last stage has fewer than 4 lanes per half.
    for (; len >= 2; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
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

  /// ML-KEM inverse: vector combine then Barrett multiply pass.
  static void mlKemInverse(NttWorkspace ws, List<int> zetas, int invScale) {
    const q = 3329;
    const n = 256;
    final f = ws.lanes;
    final v = ws.vectors;
    final qv = Int32x4(q, q, q, q);
    var k = 127;

    // len = 2 scalar stage (2 lanes per half).
    for (var start = 0; start < n; start += 4) {
      final zeta = zetas[k--];
      for (var j = start; j < start + 2; j++) {
        final fj = f[j];
        final fjl = f[j + 2];
        final sum = fj + fjl;
        f[j] = sum >= q ? sum - q : sum;
        final diff = fjl - fj;
        final reducedDiff = diff < 0 ? diff + q : diff;
        f[j + 2] = mlKemMulBarrett(zeta, reducedDiff);
      }
    }

    for (var len = 4; len <= 128; len <<= 1) {
      _inverseCombineFromHi(v, n, len, qv);
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k--];
        final hi = start + len;
        for (var j = 0; j < len; j++) {
          f[hi + j] = mlKemMulBarrett(zeta, f[hi + j]);
        }
      }
    }
    for (var i = 0; i < n; i++) {
      f[i] = mlKemMulBarrett(f[i], invScale);
    }
  }

  // ── ML-DSA (q = 8380417, n = 256) ────────────────────────────────────────

  /// ML-DSA forward: Montgomery REDC multiply pass + vector combine.
  static void mlDsaForward(NttWorkspace ws, List<int> zetasMont) {
    const q = 8380417;
    const n = 256;
    final f = ws.lanes;
    final v = ws.vectors;
    final qv = Int32x4(q, q, q, q);
    var k = 1;

    var len = 128;
    for (; len >= 4; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zetaM = zetasMont[k++];
        final hi = start + len;
        for (var j = 0; j < len; j++) {
          f[hi + j] = mlDsaRedc(zetaM * f[hi + j]);
        }
      }
      _forwardCombine(v, n, len, qv);
    }
    for (; len >= 1; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zetaM = zetasMont[k++];
        for (var j = start; j < start + len; j++) {
          final t = mlDsaRedc(zetaM * f[j + len]);
          final fj = f[j];
          final diff = fj - t;
          f[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          f[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// ML-DSA inverse: vector combine then REDC multiply pass with conjugated
  /// Montgomery twiddles.
  static void mlDsaInverse(
    NttWorkspace ws,
    List<int> zetasMont,
    int invMont,
  ) {
    const q = 8380417;
    const n = 256;
    final f = ws.lanes;
    final v = ws.vectors;
    final qv = Int32x4(q, q, q, q);
    var ik = 255;

    for (var len = 1; len < 4; len <<= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        var zetaM = zetasMont[ik--];
        zetaM = q - zetaM;
        for (var j = start; j < start + len; j++) {
          final t = f[j];
          final u = f[j + len];
          final sum = t + u;
          f[j] = sum >= q ? sum - q : sum;
          final diff = t - u;
          final d = diff < 0 ? diff + q : diff;
          f[j + len] = mlDsaRedc(zetaM * d);
        }
      }
    }

    for (var len = 4; len < n; len <<= 1) {
      _inverseCombineFromLo(v, n, len, qv);
      for (var start = 0; start < n; start += 2 * len) {
        var zetaM = zetasMont[ik--];
        zetaM = q - zetaM;
        final hi = start + len;
        for (var j = 0; j < len; j++) {
          f[hi + j] = mlDsaRedc(zetaM * f[hi + j]);
        }
      }
    }
    for (var i = 0; i < n; i++) {
      f[i] = mlDsaRedc(invMont * f[i]);
    }
  }

  // ── FN-DSA (q = 12289, n ∈ {512, 1024}) ──────────────────────────────────

  /// FN-DSA forward: k = 27 Barrett multiply pass + vector combine.
  static void fnDsaForward(NttWorkspace ws, int n, List<int> zetas) {
    const q = 12289;
    final f = ws.lanes;
    final v = ws.vectors;
    final qv = Int32x4(q, q, q, q);
    var k = 1;

    var len = n >> 1;
    for (; len >= 4; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k++];
        final hi = start + len;
        for (var j = 0; j < len; j++) {
          f[hi + j] = fnDsaReduceK27(zeta * f[hi + j]);
        }
      }
      _forwardCombine(v, n, len, qv);
    }
    for (; len >= 1; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final t = fnDsaReduceK27(zeta * f[j + len]);
          final fj = f[j];
          final diff = fj - t;
          f[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          f[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// FN-DSA inverse: vector combine then k = 27 multiply pass.
  ///
  /// Engine-level gain: 1.51× (n = 512) and 1.57× (n = 1024), both above the
  /// 1.5× adoption bar. Parity is enforced in
  /// `test/simd_ntt_parity_test.dart`.
  static void fnDsaInverse(
    NttWorkspace ws,
    int n,
    List<int> zetas,
    int invScale,
  ) {
    const q = 12289;
    final f = ws.lanes;
    final v = ws.vectors;
    final qv = Int32x4(q, q, q, q);
    var ik = n - 1;

    for (var len = 1; len < 4; len <<= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = q - zetas[ik--];
        for (var j = start; j < start + len; j++) {
          final t = f[j];
          final u = f[j + len];
          final sum = t + u;
          f[j] = sum >= q ? sum - q : sum;
          final diff = t - u;
          final d = diff < 0 ? diff + q : diff;
          f[j + len] = fnDsaReduceK27(d * zeta);
        }
      }
    }

    for (var len = 4; len < n; len <<= 1) {
      _inverseCombineFromLo(v, n, len, qv);
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = q - zetas[ik--];
        final hi = start + len;
        for (var j = 0; j < len; j++) {
          f[hi + j] = fnDsaReduceK27(zeta * f[hi + j]);
        }
      }
    }
    for (var i = 0; i < n; i++) {
      f[i] = fnDsaReduceK27(f[i] * invScale);
    }
  }

  // ── combine passes ───────────────────────────────────────────────────────

  /// `lo' = lo + t`, `hi' = lo - t` for `len >= 4`.
  static void _forwardCombine(Int32x4List v, int n, int len, Int32x4 qv) {
    final lanes = len >> 2;
    for (var start = 0; start < n; start += 2 * len) {
      final loB = start >> 2;
      final hiB = (start + len) >> 2;
      for (var i = 0; i < lanes; i++) {
        final lo = v[loB + i];
        final t = v[hiB + i];
        var sum = lo + t;
        final sn = sum - qv;
        sum = sn + ((sn >> 31) & qv);
        var d = lo - t;
        d = d + ((d >> 31) & qv);
        v[loB + i] = sum;
        v[hiB + i] = d;
      }
    }
  }

  /// `lo' = lo + u`, `hi' = u - lo` (ML-KEM inverse convention).
  static void _inverseCombineFromHi(Int32x4List v, int n, int len, Int32x4 qv) {
    final lanes = len >> 2;
    for (var start = 0; start < n; start += 2 * len) {
      final loB = start >> 2;
      final hiB = (start + len) >> 2;
      for (var i = 0; i < lanes; i++) {
        final lo = v[loB + i];
        final u = v[hiB + i];
        var sum = lo + u;
        final sn = sum - qv;
        sum = sn + ((sn >> 31) & qv);
        var d = u - lo;
        d = d + ((d >> 31) & qv);
        v[loB + i] = sum;
        v[hiB + i] = d;
      }
    }
  }

  /// `lo' = t + u`, `hi' = t - u` (ML-DSA / FN-DSA inverse convention, paired
  /// with the conjugated twiddle `-zeta`).
  static void _inverseCombineFromLo(Int32x4List v, int n, int len, Int32x4 qv) {
    final lanes = len >> 2;
    for (var start = 0; start < n; start += 2 * len) {
      final loB = start >> 2;
      final hiB = (start + len) >> 2;
      for (var i = 0; i < lanes; i++) {
        final t = v[loB + i];
        final u = v[hiB + i];
        var sum = t + u;
        final sn = sum - qv;
        sum = sn + ((sn >> 31) & qv);
        var d = t - u;
        d = d + ((d >> 31) & qv);
        v[loB + i] = sum;
        v[hiB + i] = d;
      }
    }
  }
}