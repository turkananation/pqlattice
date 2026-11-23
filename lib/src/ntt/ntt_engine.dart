import 'dart:typed_data';

import '../api/kernel_mode.dart';
import '../api/lattice_kernels.dart';
import '../mod/barrett_params.dart';
import '../mod/mod_q.dart';
import '../mod/montgomery_params.dart';
import '../poly/poly.dart';
import '../poly/poly_vec.dart';
import '../ring/ring_params.dart';
import '../simd/ntt_simd_int32x4.dart';
import '../simd/ntt_workspace.dart';
import 'ntt_params.dart';
import 'ntt_reduce.dart' as red;
import 'ntt_scalar.dart';

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

  /// In-place forward NTT (no polynomial allocation; one scratch workspace).
  ///
  /// Throws [StateError] if twiddle tables are missing. Known profiles never
  /// silently act as the identity transform.
  void forwardInPlace(Poly p) {
    _check(p);
    _requireTables();
    if (_useMontgomery) {
      _montgomeryForward(p.coeffs);
      return;
    }
    if (_reference) {
      if (ring.q == 8380417 && ring.n == 256) {
        _mlDsaForwardRef(p.coeffs);
        return;
      }
      if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
        _fnDsaForwardRef(p.coeffs);
        return;
      }
      // ML-KEM has no separate oracle recipe: the pqcrypto-parity Barrett
      // chain is the reference, so the typed scalar kernel below is the oracle.
    }
    _forward(p.coeffs);
  }

  /// In-place inverse NTT (no polynomial allocation; one scratch workspace).
  ///
  /// Throws [StateError] if twiddle tables are missing.
  void inverseInPlace(Poly p) {
    _check(p);
    _requireTables();
    if (_useMontgomery) {
      _montgomeryInverse(p.coeffs);
      return;
    }
    if (_reference) {
      if (ring.q == 8380417 && ring.n == 256) {
        _mlDsaInverseRef(p.coeffs);
        return;
      }
      if (ring.q == 12289 && (ring.n == 512 || ring.n == 1024)) {
        _fnDsaInverseRef(p.coeffs);
        return;
      }
    }
    _inverse(p.coeffs);
  }

  /// Forward dispatch: always stage into 16-byte-aligned `Int32List` lanes,
  /// run the scalar or `Int32x4` kernel, copy back.
  ///
  /// Staging is load-bearing, not cosmetic. Running the same kernel directly on
  /// `Poly.coeffs` (an `Int16List` behind a `List<int>` parameter across a
  /// method boundary) measured ~32.6 µs for an ML-KEM forward in the referee
  /// harness vs ~11.6 µs through typed lanes — the AOT compiler specializes
  /// the loop on the concrete `Int32List` callee type, which it does not do
  /// when the callee receives an interface-typed buffer. Both copies are
  /// value-exact (every butterfly stage canonicalizes into `[0, q)`, and the
  /// widest intermediate is `< 2q`), so results are bit-identical either way.
  /// See `doc/SIMD.md` §4.
  void _forward(List<int> coeffs) {
    final ws = NttWorkspace(ring.n);
    _loadLanes(coeffs, ws.lanes);
    final simd = LatticeKernels.preferSimdNtt(mode, ring, inverse: false);
    if (simd) {
      _simdForward(ws);
    } else {
      _scalarForward(ws.lanes);
    }
    _storeLanes(ws.lanes, coeffs);
  }

  void _inverse(List<int> coeffs) {
    final ws = NttWorkspace(ring.n);
    _loadLanes(coeffs, ws.lanes);
    final simd = LatticeKernels.preferSimdNtt(mode, ring, inverse: true);
    if (simd) {
      _simdInverse(ws);
    } else {
      _scalarInverse(ws.lanes);
    }
    _storeLanes(ws.lanes, coeffs);
  }

  /// Copies coefficients into workspace lanes.
  ///
  /// The `is Int16List` / `is Int32List` branches are load-bearing: they
  /// promote the source to a concrete typed-data type inside the loop, so the
  /// copy is a direct typed load rather than an interface access. Measured at
  /// engine level, this is the difference between a ~30 µs and a ~14 µs ML-KEM
  /// forward (`doc/SIMD.md` §4).
  static void _loadLanes(List<int> src, Int32List dst) {
    final n = dst.length;
    if (src is Int16List) {
      for (var i = 0; i < n; i++) {
        dst[i] = src[i];
      }
      return;
    }
    if (src is Int32List) {
      dst.setAll(0, src);
      return;
    }
    for (var i = 0; i < n; i++) {
      dst[i] = src[i];
    }
  }

  /// Copies workspace lanes back into [dst] coefficients (typed fast path).
  static void _storeLanes(Int32List src, List<int> dst) {
    final n = src.length;
    if (dst is Int16List) {
      for (var i = 0; i < n; i++) {
        dst[i] = src[i];
      }
      return;
    }
    if (dst is Int32List) {
      dst.setAll(0, src);
      return;
    }
    for (var i = 0; i < n; i++) {
      dst[i] = src[i];
    }
  }

  /// Scalar kernel dispatch on `(q, n)` using the shared certified recipes.
  void _scalarForward(Int32List f) {
    final n = ring.n;
    final zetas = params.zetas;
    if (ring.q == 3329 && n == 256) {
      NttScalar.mlKemForward(f, zetas);
      return;
    }
    if (ring.q == 8380417 && n == 256) {
      NttScalar.mlDsaForward(f, _requireMlDsaZetas());
      return;
    }
    if (ring.q == 12289 && (n == 512 || n == 1024)) {
      NttScalar.fnDsaForward(f, n, zetas);
      return;
    }
    throw StateError('forward NTT not implemented for q=${ring.q}, n=$n');
  }

  void _scalarInverse(Int32List f) {
    final n = ring.n;
    final zetas = params.zetas;
    final invScale = params.invNScale;
    if (ring.q == 3329 && n == 256) {
      NttScalar.mlKemInverse(f, zetas, invScale);
      return;
    }
    if (ring.q == 8380417 && n == 256) {
      NttScalar.mlDsaInverse(f, _requireMlDsaZetas(), _requireMlDsaInvMont());
      return;
    }
    if (ring.q == 12289 && (n == 512 || n == 1024)) {
      NttScalar.fnDsaInverse(f, n, zetas, invScale);
      return;
    }
    throw StateError('inverse NTT not implemented for q=${ring.q}, n=$n');
  }

  /// Vector kernel dispatch. Reached only when
  /// [LatticeKernels.preferSimdNtt] selected it, so the profile is known to be
  /// in the evidence table.
  void _simdForward(NttWorkspace ws) {
    final n = ring.n;
    final zetas = params.zetas;
    if (ring.q == 3329 && n == 256) {
      NttSimdInt32x4.mlKemForward(ws, zetas);
      return;
    }
    if (ring.q == 8380417 && n == 256) {
      NttSimdInt32x4.mlDsaForward(ws, _requireMlDsaZetas());
      return;
    }
    if (ring.q == 12289 && (n == 512 || n == 1024)) {
      NttSimdInt32x4.fnDsaForward(ws, n, zetas);
      return;
    }
    throw StateError('forward NTT not implemented for q=${ring.q}, n=$n');
  }

  void _simdInverse(NttWorkspace ws) {
    final n = ring.n;
    final zetas = params.zetas;
    final invScale = params.invNScale;
    if (ring.q == 3329 && n == 256) {
      NttSimdInt32x4.mlKemInverse(ws, zetas, invScale);
      return;
    }
    if (ring.q == 8380417 && n == 256) {
      NttSimdInt32x4.mlDsaInverse(
        ws,
        _requireMlDsaZetas(),
        _requireMlDsaInvMont(),
      );
      return;
    }
    if (ring.q == 12289 && (n == 512 || n == 1024)) {
      NttSimdInt32x4.fnDsaInverse(ws, n, zetas, invScale);
      return;
    }
    throw StateError('inverse NTT not implemented for q=${ring.q}, n=$n');
  }

  List<int> _requireMlDsaZetas() {
    final zetasMont = _mlDsaZetasMont;
    if (zetasMont == null) {
      throw StateError(
        'ML-DSA accelerated path requires ready Montgomery parameters',
      );
    }
    return zetasMont;
  }

  int _requireMlDsaInvMont() {
    final invMont = _mlDsaInvScaleMont;
    if (invMont == null) {
      throw StateError(
        'ML-DSA accelerated path requires ready Montgomery parameters',
      );
    }
    return invMont;
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

  /// ML-DSA accelerated path: FIPS 204 ring NTT with inlined 32-bit-word
  /// Montgomery REDC butterflies (plain-domain arrangement), run by
  /// [NttScalar.mlDsaForward] on the coefficient buffer or
  /// [NttSimdInt32x4.mlDsaForward] on staged `Int32List` lanes.
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
  ///
  /// FN-DSA accelerated path: forward NTT with inlined k=27 single-guard
  /// Barrett butterflies (mu = 10921 = floor(2^27 / 12289)), run by
  /// [NttScalar.fnDsaForward] / [NttSimdInt32x4.fnDsaForward].
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
  static int fnDsaReduceK27(int prod) => red.fnDsaReduceK27(prod);

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

  /// Precomputes Montgomery-domain twiddles: `zetasMont[k] = zetas[k] * R mod q`.
  /// This avoids calling [ModQ.toMont] on every butterfly in the inner loop.
  static List<int> _precomputeMontgomeryZetas(
    List<int> zetas,
    MontgomeryParams mont,
  ) {
    return zetas.map((z) => ModQ.toMont(z, mont)).toList();
  }
}
