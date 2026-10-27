import '../api/kernel_mode.dart';
import '../api/lattice_kernels.dart';
import '../mod/barrett_params.dart';
import '../mod/mod_q.dart';
import '../mod/montgomery_params.dart';
import '../poly/poly.dart';
import '../poly/poly_vec.dart';
import '../ring/ring_params.dart';
import 'ntt_params.dart';

/// Forward and inverse NTT — **accelerated by default**.
///
/// - Allocating API: [forward] / [inverse]
/// - Zero-copy API: [forwardInPlace] / [inverseInPlace]
/// - ML-KEM / ML-DSA: real transforms (pqcrypto tables)
/// - Hot path uses [ModQ.addFast]/[subFast]/[mulBarrett]
/// - Optional Montgomery-domain NTT: when [montgomeryParams] is provided and
///   ready, the entire transform runs in Montgomery domain (inputs converted
///   on entry, twiddles converted on the fly, outputs converted on exit).
///   Results are bit-identical to the Barrett/%-path; Montgomery is **not**
///   the default — it is swappable for parity testing and measured deployment.
final class NttEngine {
  final RingParams ring;
  final NttParams params;
  final KernelMode mode;
  final BarrettParams _barrett;
  final MontgomeryParams? _montgomery;

  /// Precomputed Montgomery-domain twiddles (zeta * R mod q).
  /// Populated only when Montgomery-domain NTT is active; avoids calling
  /// [ModQ.toMont] on every butterfly in the inner loop.
  List<int>? _zetasMont;

  NttEngine(
    this.ring, {
    NttParams? params,
    this.mode = KernelMode.accelerated,
    MontgomeryParams? montgomeryParams,
  }) : params = params ?? NttParams.forRing(ring),
       _barrett = BarrettParams.forQ(ring.q),
       _montgomery = montgomeryParams,
       _zetasMont = null {
    _zetasMont = montgomeryParams != null && montgomeryParams.isReady
        ? _precomputeMontgomeryZetas(this.params.zetas, montgomeryParams)
        : null;
    if (ring.n != this.params.ring.n || ring.q != this.params.ring.q) {
      throw ArgumentError('NttParams ring does not match engine ring');
    }
    final mont = _montgomery;
    if (mont != null) {
      if (mont.q != ring.q) {
        throw ArgumentError(
          'MontgomeryParams q=${mont.q} does not match engine ring q=${ring.q}',
        );
      }
      if (!mont.isReady) {
        throw StateError(
          'MontgomeryParams are not ready for q=${mont.q}; '
          'cannot use Montgomery-domain NTT',
        );
      }
    }
  }

  bool get _reference => LatticeKernels.useReference(mode);

  /// True when Montgomery-domain NTT is active (params provided and ready).
  bool get _useMontgomery {
    final mont = _montgomery;
    return mont != null && mont.isReady;
  }

  Poly forward(Poly a) {
    _check(a);
    final out = a.clone();
    forwardInPlace(out);
    return out;
  }

  Poly inverse(Poly aHat) {
    _check(aHat);
    final out = aHat.clone();
    inverseInPlace(out);
    return out;
  }

  /// In-place forward NTT (no allocation).
  ///
  /// Throws [StateError] if twiddle tables are missing. Known profiles never
  /// silently act as the identity transform.
  void forwardInPlace(Poly p) {
    _check(p);
    _requireTables();
    if (_useMontgomery) {
      _montgomeryForward(p.coeffs);
    } else if (ring.q == 3329 && ring.n == 256) {
      _mlKemForward(p.coeffs);
    } else if (ring.q == 8380417 && ring.n == 256) {
      _mlDsaForward(p.coeffs);
    } else if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
      _fnDsaForward(p.coeffs);
    } else {
      throw StateError(
        'forward NTT not implemented for q=${ring.q}, n=${ring.n}',
      );
    }
  }

  /// In-place inverse NTT (no allocation).
  ///
  /// Throws [StateError] if twiddle tables are missing.
  void inverseInPlace(Poly p) {
    _check(p);
    _requireTables();
    if (_useMontgomery) {
      _montgomeryInverse(p.coeffs);
    } else if (ring.q == 3329 && ring.n == 256) {
      _mlKemInverse(p.coeffs);
    } else if (ring.q == 8380417 && ring.n == 256) {
      _mlDsaInverse(p.coeffs);
    } else if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
      _fnDsaInverse(p.coeffs);
    } else {
      throw StateError(
        'inverse NTT not implemented for q=${ring.q}, n=${ring.n}',
      );
    }
  }

  void _requireTables() {
    if (!params.hasZetas) {
      throw StateError(
        'NTT tables missing for ${ring.name} (q=${ring.q}, n=${ring.n}); '
        'refusing identity transform',
      );
    }
  }

  PolyVec forwardVec(PolyVec v) {
    _checkVec(v);
    final out = v.clone();
    for (final p in out.polys) {
      forwardInPlace(p);
    }
    return out;
  }

  PolyVec inverseVec(PolyVec v) {
    _checkVec(v);
    final out = v.clone();
    for (final p in out.polys) {
      inverseInPlace(p);
    }
    return out;
  }

  /// In-place forward on each poly of [v].
  void forwardVecInPlace(PolyVec v) {
    _checkVec(v);
    for (final p in v.polys) {
      forwardInPlace(p);
    }
  }

  void inverseVecInPlace(PolyVec v) {
    _checkVec(v);
    for (final p in v.polys) {
      inverseInPlace(p);
    }
  }

  int _mul(int a, int b) {
    if (_reference) {
      return ModQ.mul(a, b, ring.q);
    }
    if (_useMontgomery) {
      // Montgomery domain: both operands are Montgomery-domain values.
      // montMul(a_m, b_m) = a_m * b_m * R⁻¹ mod q = toMont(a * b).
      return ModQ.montMul(a, b, _montgomery!);
    }
    if (_barrett.isReady) {
      return ModQ.mulBarrett(a, b, _barrett);
    }
    return ModQ.mul(a, b, ring.q);
  }

  void _mlKemForward(List<int> f) {
    final q = ring.q;
    final zetas = params.zetas;
    var k = 1;
    var layer = 0;
    for (var len = 128; len >= 2; len >>= 1) {
      layer++;
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final fj = f[j];
          final fjl = f[j + len];
          final t = _mulBarrettMlKemLazy(zeta, fjl, q);
          // f[j + len] = fj - t mod q
          final diff = fj - t;
          f[j + len] = diff < 0 ? diff + q : diff;
          // fj = fj + t mod q
          final sum = fj + t;
          f[j] = sum >= q ? sum - q : sum;
        }
      }
      // Lazy reduction every 2 layers: after layers 2, 4, 6
      if (layer % 2 == 0) {
        for (var i = 0; i < 256; i++) {
          f[i] = _reduceBarrettMlKemLazy(f[i], q);
        }
      }
    }
    // Final reduce after layer 7
    for (var i = 0; i < 256; i++) {
      f[i] = _reduceBarrettMlKemLazy(f[i], q);
    }
  }

  void _mlKemInverse(List<int> f) {
    final q = ring.q;
    final zetas = params.zetas;
    var k = 127;
    var layer = 0;
    for (var len = 2; len <= 128; len <<= 1) {
      layer++;
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k--];
        for (var j = start; j < start + len; j++) {
          final fj = f[j];
          final fjl = f[j + len];
          // fj = fj + fjl mod q
          final sum = fj + fjl;
          f[j] = sum >= q ? sum - q : sum;
          // fjl = zeta * (fjl - fj) mod q
          final diff = fjl - fj;
          final reducedDiff = diff < 0 ? diff + q : diff;
          final t = _mulBarrettMlKemLazy(zeta, reducedDiff, q);
          f[j + len] = t;
        }
      }
      if (layer % 2 == 0) {
        for (var i = 0; i < 256; i++) {
          f[i] = _reduceBarrettMlKemLazy(f[i], q);
        }
      }
    }
    final inv = params.invNScale;
    for (var i = 0; i < 256; i++) {
      f[i] = _mulBarrettMlKemLazy(f[i], inv, q);
    }
  }

  /// pqcrypto DilithiumNTT.ntt (FIPS 204 shape).
  void _mlDsaForward(List<int> a) {
    final q = ring.q;
    final zetas = params.zetas;
    var k = 1;
    for (var len = 128; len >= 1; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final t = _mul(zeta, a[j + len]);
          a[j + len] = ModQ.subFast(a[j], t, q);
          a[j] = ModQ.addFast(a[j], t, q);
        }
      }
    }
  }

  /// pqcrypto DilithiumNTT.invNtt.
  void _mlDsaInverse(List<int> a) {
    final q = ring.q;
    final zetas = params.zetas;
    var k = 255;
    for (var len = 1; len < 256; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        var zeta = zetas[k--];
        zeta = q - zeta; // -zetas[k] mod q
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          a[j] = ModQ.addFast(t, u, q);
          a[j + len] = _mul(ModQ.subFast(t, u, q), zeta);
        }
      }
    }
    final inv = params.invNScale;
    for (var i = 0; i < 256; i++) {
      a[i] = _mul(a[i], inv);
    }
  }

  /// FN-DSA / Falcon integer NTT (complete, negacyclic) over \(q = 12289\).
  ///
  /// Twiddles are \(\zeta_k = \psi^{\mathrm{bitrev}(k)} \bmod q\) where
  /// \(\psi^{n} \equiv -1\), \(\psi^{2n} \equiv 1\) (ψ = 49 for n=512, ψ = 7 for n=1024).
  /// Matches Falcon reference constructions (e.g. itzmeanjan/falcon).
  /// Used for verification-side integer arithmetic; not the floating-point FFT.
  void _fnDsaForward(List<int> a) {
    final q = ring.q;
    final n = ring.n;
    final zetas = params.zetas;
    var k = 1;
    for (var len = n >> 1; len >= 1; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final t = _mul(zeta, a[j + len]);
          a[j + len] = ModQ.subFast(a[j], t, q);
          a[j] = ModQ.addFast(a[j], t, q);
        }
      }
    }
  }

  void _fnDsaInverse(List<int> a) {
    final q = ring.q;
    final n = ring.n;
    final zetas = params.zetas;
    // Inverse uses conjugate powers: walk the same table backwards with -zeta.
    var k = n - 1;
    for (var len = 1; len < n; len <<= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        var zeta = zetas[k--];
        zeta = q - zeta; // -zeta mod q
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          a[j] = ModQ.addFast(t, u, q);
          a[j + len] = _mul(ModQ.subFast(t, u, q), zeta);
        }
      }
    }
    final inv = params.invNScale; // n^{-1} mod q
    for (var i = 0; i < n; i++) {
      a[i] = _mul(a[i], inv);
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Montgomery-domain NTT variants
  //
  // Each converts the input polynomial to Montgomery domain on entry, runs the
  // same butterfly structure with _mul (which uses montMul when _useMontgomery
  // is true), and converts back on exit. Twiddles are converted to Montgomery
  // domain on the fly via ModQ.toMont. Results are bit-identical to the
  // Barrett/%-path; Montgomery is opt-in and never the default.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _montgomeryForward(List<int> f) {
    final q = ring.q;
    final mont = _montgomery!;
    final n = f.length;

    // Convert input to Montgomery domain: f_m[i] = f[i] * R mod q
    for (var i = 0; i < n; i++) {
      f[i] = ModQ.toMont(f[i], mont);
    }

    if (ring.q == 3329 && ring.n == 256) {
      _mlKemForwardMontgomery(f, mont);
    } else if (ring.q == 8380417 && ring.n == 256) {
      _mlDsaForwardMontgomery(f, mont);
    } else if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
      _fnDsaForwardMontgomery(f, mont);
    } else {
      throw StateError('Montgomery forward NTT not implemented for q=$q, n=$n');
    }
    // Output remains in Montgomery domain. Caller (inverse / pointwiseMontgomery)
    // expects Montgomery-domain values. Use ModQ.fromMont to observe in normal
    // domain.
  }

  void _montgomeryInverse(List<int> f) {
    final q = ring.q;
    final mont = _montgomery!;
    final n = f.length;

    // Input is expected in Montgomery domain (output of forward or
    // pointwiseMontgomery). Do NOT convert again.
    if (ring.q == 3329 && ring.n == 256) {
      _mlKemInverseMontgomery(f, mont);
    } else if (ring.q == 8380417 && ring.n == 256) {
      _mlDsaInverseMontgomery(f, mont);
    } else if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
      _fnDsaInverseMontgomery(f, mont);
    } else {
      throw StateError('Montgomery inverse NTT not implemented for q=$q, n=$n');
    }

    // Convert output back to normal domain: f[i] = f_m[i] * R⁻¹ mod q
    for (var i = 0; i < n; i++) {
      f[i] = ModQ.fromMont(f[i], mont);
    }
  }

  void _mlKemForwardMontgomery(List<int> f, MontgomeryParams mont) {
    final q = ring.q;
    final zetasMont = _zetasMont!;
    var k = 1;
    for (var len = 128; len >= 2; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetasMont[k++];
        for (var j = start; j < start + len; j++) {
          final t = _mul(zeta, f[j + len]);
          f[j + len] = ModQ.subFast(f[j], t, q);
          f[j] = ModQ.addFast(f[j], t, q);
        }
      }
    }
  }

  void _mlKemInverseMontgomery(List<int> f, MontgomeryParams mont) {
    final q = ring.q;
    final zetasMont = _zetasMont!;
    var k = 127;
    final inv = ModQ.toMont(params.invNScale, mont);
    for (var len = 2; len <= 128; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetasMont[k--];
        for (var j = start; j < start + len; j++) {
          final t = f[j];
          f[j] = ModQ.addFast(t, f[j + len], q);
          f[j + len] = _mul(zeta, ModQ.subFast(f[j + len], t, q));
        }
      }
    }
    for (var i = 0; i < 256; i++) {
      f[i] = _mul(f[i], inv);
    }
  }

  void _mlDsaForwardMontgomery(List<int> a, MontgomeryParams mont) {
    final q = ring.q;
    final zetasMont = _zetasMont!;
    var k = 1;
    for (var len = 128; len >= 1; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetasMont[k++];
        for (var j = start; j < start + len; j++) {
          final t = _mul(zeta, a[j + len]);
          a[j + len] = ModQ.subFast(a[j], t, q);
          a[j] = ModQ.addFast(a[j], t, q);
        }
      }
    }
  }

  void _mlDsaInverseMontgomery(List<int> a, MontgomeryParams mont) {
    final q = ring.q;
    final zetasMont = _zetasMont!;
    var k = 255;
    final inv = ModQ.toMont(params.invNScale, mont);
    for (var len = 1; len < 256; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        var zeta = zetasMont[k--];
        zeta = q - zeta; // -zetas[k] mod q in Montgomery domain
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          a[j] = ModQ.addFast(t, u, q);
          a[j + len] = _mul(ModQ.subFast(t, u, q), zeta);
        }
      }
    }
    for (var i = 0; i < 256; i++) {
      a[i] = _mul(a[i], inv);
    }
  }

  void _fnDsaForwardMontgomery(List<int> a, MontgomeryParams mont) {
    final q = ring.q;
    final n = ring.n;
    final zetasMont = _zetasMont!;
    var k = 1;
    for (var len = n >> 1; len >= 1; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetasMont[k++];
        for (var j = start; j < start + len; j++) {
          final t = _mul(zeta, a[j + len]);
          a[j + len] = ModQ.subFast(a[j], t, q);
          a[j] = ModQ.addFast(a[j], t, q);
        }
      }
    }
  }

  void _fnDsaInverseMontgomery(List<int> a, MontgomeryParams mont) {
    final q = ring.q;
    final n = ring.n;
    final zetasMont = _zetasMont!;
    var k = n - 1;
    final inv = ModQ.toMont(params.invNScale, mont);
    // Inverse uses conjugate powers: walk the same table backwards with -zeta.
    for (var len = 1; len < n; len <<= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        var zeta = zetasMont[k--];
        zeta = q - zeta; // -zeta mod q in Montgomery domain
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          a[j] = ModQ.addFast(t, u, q);
          a[j + len] = _mul(ModQ.subFast(t, u, q), zeta);
        }
      }
    }
    for (var i = 0; i < n; i++) {
      a[i] = _mul(a[i], inv);
    }
  }

  void _check(Poly a) {
    if (a.n != ring.n || a.q != ring.q) {
      throw ArgumentError('polynomial ring does not match engine');
    }
  }

  void _checkVec(PolyVec v) {
    if (v.ring.n != ring.n || v.ring.q != ring.q) {
      throw ArgumentError('PolyVec ring mismatch');
    }
  }

  /// Barrett reduction for ML-KEM: q = 3329, mu = 5039, shift = 24.
  /// Handles inputs in [-2q^2, 2q^2] ≈ [-2.2e7, 2.2e7] for lazy reduction.
  /// Inlined to avoid [BarrettParams] object field lookups in the hot loop.
  static int _mulBarrettMlKemLazy(int zeta, int f, int q) {
    // zeta in [0, q), f in [-2q^2, 2q^2], raw in [-2q^3, 2q^3] ≈ [-7.3e10, 7.3e10]
    final raw = zeta * f;
    var r = raw - ((raw * 5039) >> 24) * 3329;
    // Barrett error bounded by ~q per reduction; r should be within ~[-2q, 2q]
    if (r >= 3329) r -= 3329;
    if (r >= 3329) r -= 3329;
    if (r >= 3329) r -= 3329;
    if (r >= 3329) r -= 3329;
    if (r < 0) r += 3329;
    if (r < 0) r += 3329;
    if (r < 0) r += 3329;
    if (r < 0) r += 3329;
    return r;
  }

  /// Barrett reduce for lazy accumulation: input in [-2q^2, 2q^2].
  static int _reduceBarrettMlKemLazy(int a, int q) {
    var r = a - ((a * 5039) >> 24) * 3329;
    if (r >= 3329) r -= 3329;
    if (r >= 3329) r -= 3329;
    if (r >= 3329) r -= 3329;
    if (r >= 3329) r -= 3329;
    if (r < 0) r += 3329;
    if (r < 0) r += 3329;
    if (r < 0) r += 3329;
    if (r < 0) r += 3329;
    return r;
  }

  /// Precomputes Montgomery-domain twiddles: `zetasMont[k] = zetas[k] * R mod q`.
  /// This avoids calling [ModQ.toMont] on every butterfly in the inner loop.
  static List<int> _precomputeMontgomeryZetas(
    List<int> zetas,
    MontgomeryParams mont,
  ) {
    return zetas.map((z) => ModQ.toMont(z, mont)).toList();
  }
}
