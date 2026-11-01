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

  /// Montgomery-form twiddles for the ML-DSA accelerated default path
  /// (plain-domain arrangement, no input/output conversions). Independent of
  /// the opt-in Montgomery-domain NTT twiddles above.
  List<int>? _mlDsaZetasMont;

  /// Montgomery-form \(n^{-1}\) scale for the ML-DSA accelerated default path.
  int? _mlDsaInvScaleMont;

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
    if (ring.q == 8380417 && this.params.hasZetas) {
      final mont = MontgomeryParams.forQ(ring.q);
      if (mont.isReady) {
        _mlDsaZetasMont = _precomputeMontgomeryZetas(this.params.zetas, mont);
        _mlDsaInvScaleMont = ModQ.toMont(this.params.invNScale, mont);
      }
    }
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
      if (_reference) {
        _mlDsaForwardRef(p.coeffs);
      } else {
        _mlDsaForward(p.coeffs);
      }
    } else if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
      if (_reference) {
        _fnDsaForwardRef(p.coeffs);
      } else {
        _fnDsaForward(p.coeffs);
      }
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
      if (_reference) {
        _mlDsaInverseRef(p.coeffs);
      } else {
        _mlDsaInverse(p.coeffs);
      }
    } else if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
      if (_reference) {
        _fnDsaInverseRef(p.coeffs);
      } else {
        _fnDsaInverse(p.coeffs);
      }
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
    for (var len = 128; len >= 2; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final fj = f[j];
          final fjl = f[j + len];
          final t = _mulBarrettMlKem(zeta, fjl);
          // f[j + len] = f[j] - t mod q
          final diff = fj - t;
          f[j + len] = diff < 0 ? diff + q : diff;
          // f[j] = f[j] + t mod q
          final sum = fj + t;
          f[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  void _mlKemInverse(List<int> f) {
    final q = ring.q;
    final zetas = params.zetas;
    var k = 127;
    for (var len = 2; len <= 128; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zeta = zetas[k--];
        for (var j = start; j < start + len; j++) {
          final fj = f[j];
          final fjl = f[j + len];
          // f[j] = f[j] + f[j + len] mod q
          final sum = fj + fjl;
          f[j] = sum >= q ? sum - q : sum;
          // f[j + len] = zeta * (f[j + len] - fj) mod q
          final diff = fjl - fj;
          final reducedDiff = diff < 0 ? diff + q : diff;
          final t = _mulBarrettMlKem(zeta, reducedDiff);
          f[j + len] = t;
        }
      }
    }
    final inv = params.invNScale;
    for (var i = 0; i < 256; i++) {
      f[i] = _mulBarrettMlKem(f[i], inv);
    }
  }

  /// Reference (oracle) path: `pqcrypto DilithiumNTT.ntt` (FIPS 204 shape),
  /// preserved verbatim — `_mul` graph with the legacy Barrett chain.
  void _mlDsaForwardRef(List<int> a) {
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

  /// Reference (oracle) path: `pqcrypto DilithiumNTT.invNtt`, preserved
  /// verbatim — `_mul` graph with the legacy Barrett chain.
  void _mlDsaInverseRef(List<int> a) {
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

  /// ML-DSA accelerated path: FIPS 204 ring NTT with fully inlined 32-bit-word
  /// Montgomery REDC butterflies (plain-domain arrangement).
  ///
  /// Twiddles are precomputed in Montgomery form ([_mlDsaZetasMont]) and the
  /// polynomial stays in the plain domain throughout: REDC(zetaM · x) ≡
  /// zeta · x, so outputs are bit-identical to the classic Barrett path with
  /// zero input or output conversions.
  ///
  /// Bounds: prod < q^2 < 2^46; (prod + m·q) < 2^46 + R·q < 2^56 — wrap-free
  /// in 64-bit Dart ints; no hardware division on this path. Fail-closed if
  /// the Montgomery parameters are unavailable. See
  /// test/mldsa_wrap_boundary_test.dart for the executable boundary evidence.
  void _mlDsaForward(List<int> a) {
    final zetasMont = _mlDsaZetasMont;
    if (zetasMont == null) {
      throw StateError(
        'ML-DSA accelerated path requires ready Montgomery parameters',
      );
    }
    const q = 8380417;
    var k = 1;
    for (var len = 128; len >= 1; len >>= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final zetaM = zetasMont[k++];
        for (var j = start; j < start + len; j++) {
          final t = _redcMlDsa(zetaM * a[j + len]);
          final fj = a[j];
          final diff = fj - t;
          a[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          a[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// ML-DSA accelerated inverse with the same inlined REDC butterflies:
  /// conjugate twiddles (`-zeta` in Montgomery form) and a Montgomery-form
  /// \(n^{-1}\) scale so the output is the plain-domain result, identical to
  /// the classic Barrett path. Bounds as documented on [_mlDsaForward].
  void _mlDsaInverse(List<int> a) {
    final zetasMont = _mlDsaZetasMont;
    final invMont = _mlDsaInvScaleMont;
    if (zetasMont == null || invMont == null) {
      throw StateError(
        'ML-DSA accelerated path requires ready Montgomery parameters',
      );
    }
    const q = 8380417;
    var ik = 255;
    for (var len = 1; len < 256; len <<= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        var zetaM = zetasMont[ik--];
        zetaM = q - zetaM; // -zetas[k] in Montgomery form
        for (var j = start; j < start + len; j++) {
          final t = a[j];
          final u = a[j + len];
          final sum = t + u;
          a[j] = sum >= q ? sum - q : sum;
          final diff = t - u;
          final d = diff < 0 ? diff + q : diff;
          a[j + len] = _redcMlDsa(zetaM * d);
        }
      }
    }
    for (var i = 0; i < 256; i++) {
      a[i] = _redcMlDsa(invMont * a[i]);
    }
  }

  /// Single-limb 32-bit-word Montgomery REDC for q = 8380417:
  /// `m = ((prod mod 2^32) · nPrime) mod 2^32; u = (prod + m·q) >> 32`, one
  /// conditional guard. Input bound prod < 2^46 → (prod + m·q) < 2^56, so the
  /// sum cannot wrap a 64-bit signed int. nPrime = -q^{-1} mod 2^32
  /// (= 4236238847, shipped in MontgomeryParams for this ring).
  static int _redcMlDsa(int prod) {
    const q = 8380417;
    const mask = 0xFFFFFFFF;
    const nPrime = 4236238847;
    final m = ((prod & mask) * nPrime) & mask;
    var u = (prod + m * q) >> 32;
    if (u >= q) u -= q;
    return u;
  }

  /// FN-DSA accelerated path: forward NTT with fully inlined k=27
  /// single-guard Barrett butterflies (mu = 10921 = floor(2^27 / 12289)).
  ///
  /// Twiddle construction (shared with the reference path): tables are
  /// \(\zeta_k = \psi^{\mathrm{bitrev}(k)} \bmod q\) where \(\psi^{n} \equiv
  /// -1\), \(\psi^{2n} \equiv 1\) (ψ = 49 for n=512, ψ = 7 for n=1024),
  /// matching Falcon reference constructions.
  ///
  /// Provenance: product bound raw < q^2 = 151,019,521 < 2^28 — one
  /// conditional correction in expectation, the `%` escape retained as a
  /// defensive guard but unreachable for in-range products; certified by the
  /// exhaustive residue test over all 12289^2 products in
  /// test/fndsa_exhaustive_residue_test.dart.
  void _fnDsaForward(List<int> a) {
    final q = ring.q;
    final n = ring.n;
    final zetas = params.zetas;
    var k = 1;
    for (var len = n >> 1; len >= 1; len >>= 1) {
      for (var start = 0; start < n; start += 2 * len) {
        final zeta = zetas[k++];
        for (var j = start; j < start + len; j++) {
          final raw = zeta * a[j + len];
          final t = fnDsaReduceK27(raw);
          final fj = a[j];
          final diff = fj - t;
          a[j + len] = diff < 0 ? diff + q : diff;
          final sum = fj + t;
          a[j] = sum >= q ? sum - q : sum;
        }
      }
    }
  }

  /// FN-DSA accelerated inverse: conjugate twiddles (`-zeta` mod q) walking
  /// the same table backwards, and a k=27 single-guard final \(n^{-1}\)
  /// scale. Outputs are the canonical plain-domain result, consistent with
  /// the reference path. Product bounds as documented on [_fnDsaForward].
  void _fnDsaInverse(List<int> a) {
    final q = ring.q;
    final n = ring.n;
    final zetas = params.zetas;
    final inv = params.invNScale; // n^{-1} mod q
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
      a[i] = fnDsaReduceK27(a[i] * inv);
    }
  }

  /// Single-guard Barrett reduction for the FN-DSA product family:
  /// q = 12289, shift = 27, mu = 10921 = floor(2^27 / 12289).
  ///
  /// Documented input bound: 0 <= prod < q^2 = 151,019,521 < 2^28 (covers all
  /// butterfly and final-scale products). Two conditional subtractions, one
  /// negative fix, and a defensive `%` escape that is unreachable for
  /// in-range products (0 corrections observed under the bound). Exhaustively
  /// certified over all 12289^2 products by
  /// test/fndsa_exhaustive_residue_test.dart, which exercises this exact
  /// production chain.
  static int fnDsaReduceK27(int prod) {
    const q = 12289;
    const mu = 10921;
    final quot = (prod * mu) >> 27;
    var r = prod - quot * q;
    r = r >= q ? r - q : r;
    r = r >= q ? r - q : r;
    if (r < 0) r += q;
    if (r >= q) r %= q;
    return r;
  }

  /// Reference (oracle) path: FN-DSA / Falcon integer NTT (complete,
  /// negacyclic) over \(q = 12289\), preserved verbatim — `_mul` graph with
  /// the legacy Barrett chain.
  void _fnDsaForwardRef(List<int> a) {
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

  /// Reference (oracle) path for the FN-DSA inverse NTT, preserved verbatim —
  /// `_mul` graph with the legacy Barrett chain.
  void _fnDsaInverseRef(List<int> a) {
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

  /// Barrett reduction for ML-KEM: q = 3329, v = 20159, shift = 26.
  /// 20159 = ceil(2^26 / 3329) — pqcrypto-parity single-guard form.
  /// Inlined to avoid [BarrettParams] object field lookups in the hot loop.
  /// Input bound: 0 <= a, b < q, so raw = a * b < q^2 ≈ 1.1e7 < 2^24;
  /// certified by exhaustive residue check over all 3329^2 products.
  static int _mulBarrettMlKem(int a, int b) {
    final raw = a * b;
    final quot = (raw * 20159) >> 26;
    var r = raw - quot * 3329;
    if (r < 0 || r >= 3329) r %= 3329;
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
