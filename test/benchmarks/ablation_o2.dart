/// Stage-O2 attribution ablation: fused two-layer butterflies + basemul
/// call-graph removal.
///
/// Pairing per shipped ring (same discipline as `ablation_step0.dart` — no
/// production file is touched by this harness):
///
/// - `fusedF`/`fusedI` — forward and inverse passes fusing two adjacent
///   butterfly layers into one super-block pass with direct twiddle indexing,
///   so every butterfly uses the identical zeta it uses in the production
///   loop. The reduce chain is an exact replica of the shipped chain for that
///   ring (ML-KEM v=20159/26 single-guard; ML-DSA 32-bit-word Montgomery REDC
///   with Montgomery-form twiddles; FN-DSA k=27 chain, mu=10921).
/// - `inlineB` — basemul with the exact shipped reduce recipe but every ModQ
///   call expanded inline (call-graph removal probe).
/// - `redc2PW` — ML-DSA only: wrap-free Montgomery pointwise candidate on
///   plain-domain values (aMont/bMont precomputed in setup): REDC(aM*bM) =
///   a*b*R mod q, then REDC again -> a*b mod q. Division-free by construction;
///   motivated by the escape-hot legacy k=48 chain (E16 wrap threshold).
///   Production adoption would ride the Montgomery-domain NTT variant.
///
/// Every candidate kernel is checked coefficient-identical against the
/// production engine (forward-only parity and full pair parity) before any
/// timing. Any mismatch aborts before timing.
///
/// Output: TSV rows on stdout (ring/arm per-iteration ns); parity, projection
/// and gate lines on stderr. Gate reads the within-session paired projection:
/// <= -15% pipeline projection -> build; > -10% -> stop (refuted).
///
/// Usage:
///   dart compile exe test/benchmarks/ablation_o2.dart -o `<binary>`
///   `<binary>`                            # AOT — claim-quality numbers
///   `<binary>` --rounds 40 --iters 200    # more trials
///
/// Bench-only; never imported by library code.
library;

import 'dart:io';
import 'dart:math';

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

void main(List<String> args) {
  var rounds = 24;
  var iters = 100;
  var skipTiming = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--rounds':
        rounds = int.parse(args[++i]);
      case '--iters':
        iters = int.parse(args[++i]);
      case '--skip-timing':
        skipTiming = true;
      case '--help':
        stderr.writeln(
          'Usage: ablation_o2.dart [--rounds N] [--iters N] [--skip-timing]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }

  final ok = _runParity();
  if (!ok) {
    stderr.writeln('ABORT: parity failure — an O2 candidate kernel is wrong.');
    exit(1);
  }
  stderr.writeln(
    'PARITY: all O2 candidate kernels match production output '
    '(forward-only and full pair, two input patterns).',
  );
  if (skipTiming) {
    stderr.writeln('Timing skipped (--skip-timing).');
    exit(0);
  }

  final ctx = BenchmarkContext.capture();
  final buildMode = _detectBuildMode();
  stderr.writeln(
    'context sdk=${ctx.sdkVersion.split(" ").first} os=${ctx.os} '
    'cpus=${ctx.cpuCount} sha=${ctx.gitSha} mode=$buildMode '
    'rounds=$rounds iters=$iters',
  );

  print('ring\tarm\tmedianNs\tmeanNs\tminNs\tmaxNs\trstdPct\ttrials');

  const warmup = 200;

  _runRing(
    ring: RingParams.mlKem,
    ringName: 'mlKem',
    shippedFwdNs: 36773,
    shippedPipelineNs: 142595,
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  _runRing(
    ring: RingParams.mlDsa,
    ringName: 'mlDsa',
    shippedFwdNs: 44117,
    shippedPipelineNs: 158107,
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  _runRing(
    ring: RingParams.fnDsa512,
    ringName: 'fnDsa512',
    shippedFwdNs: 111648,
    shippedPipelineNs: 388409,
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  _runRing(
    ring: RingParams.fnDsa1024,
    ringName: 'fnDsa1024',
    shippedFwdNs: 251989,
    shippedPipelineNs: 837398,
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  drainBenchmarkSink();
  exit(0);
}

String _detectBuildMode() {
  final script = Platform.script.toString();
  if (script.endsWith('.exe') ||
      script.contains('snapshot') ||
      !script.endsWith('.dart')) {
    return 'aot';
  }
  return 'jit';
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-ring runner: forward-only, inverse-only, basemul arms + projections
// ─────────────────────────────────────────────────────────────────────────────

void _runRing({
  required RingParams ring,
  required String ringName,
  required int shippedFwdNs,
  required int shippedPipelineNs,
  required int rounds,
  required int iters,
  required int warmup,
}) {
  final engine = NttEngine(ring);
  final ntt = NttParams.forRing(ring);
  final base = _benchPoly(ring, 0x2BEEF5 ^ ring.q);

  final q = ring.q;

  // Setup: pre-built Montgomery tables for the ML-DSA fused kernels so the
  // timed arm never pays table construction (mirrors production precompute).
  List<int>? zetasMont;
  int? invMont;
  if (q == 8380417) {
    final mont = MontgomeryParams.forQ(q);
    zetasMont = ntt.zetas.map((z) => ModQ.toMont(z, mont)).toList();
    invMont = ModQ.toMont(ntt.invNScale, mont);
  }

  // Setup lanes.
  // Production forward lane (input to production inverse-only arm).
  final baseFwdProd = base.clone();
  engine.forwardInPlace(baseFwdProd);
  // Fused forward lane (input to fused inverse-only arm).
  final baseFwdFused = base.clone();
  _fusedFwd(ntt, baseFwdFused.coeffs, zetasMont: zetasMont);

  // Basemul lanes: NTT-domain a/b hats from deterministic polys.
  final aHat = base.clone();
  engine.forwardInPlace(aHat);
  final bPoly = Poly.fromCoeffs(ring, _patternCoeffs(ring, 1));
  engine.forwardInPlace(bPoly);
  final destProd = Poly.zero(ring);
  final destInl = Poly.zero(ring);
  List<int>? aMont;
  List<int>? bMont;
  if (q == 8380417) {
    final mont = MontgomeryParams.forQ(q);
    aMont = aHat.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
    bMont = bPoly.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
  }

  final arms = <String, List<double>>{};

  void runArm(String name, void Function() body, Poly lane) {
    final (ns, _) = measureRounds(
      body,
      iterations: iters,
      rounds: rounds,
      warmup: warmup,
      observe: (i) => observeInt(lane.coeffs[0]),
    );
    arms[name] = ns;
  }

  {
    final p = Poly.zero(ring);
    runArm('prodF', () {
      p.coeffs.setAll(0, base.coeffs);
      engine.forwardInPlace(p);
    }, p);

    final p2 = Poly.zero(ring);
    runArm('fusedF', () {
      p2.coeffs.setAll(0, base.coeffs);
      _fusedFwd(ntt, p2.coeffs, zetasMont: zetasMont);
    }, p2);

    final p3 = Poly.zero(ring);
    runArm('prodI', () {
      p3.coeffs.setAll(0, baseFwdProd.coeffs);
      engine.inverseInPlace(p3);
    }, p3);

    final p4 = Poly.zero(ring);
    runArm('fusedI', () {
      p4.coeffs.setAll(0, baseFwdFused.coeffs);
      _fusedInv(ntt, p4.coeffs, zetasMont: zetasMont, invMont: invMont);
    }, p4);

    final b1 = destProd;
    runArm('prodB', () {
      if (q == 3329) {
        Basemul.mlKemPairsInPlace(b1, aHat, bPoly);
      } else {
        Basemul.pointwiseInPlace(b1, aHat, bPoly, ring);
      }
    }, b1);

    final b2 = destInl;
    runArm('inlineB', () {
      if (q == 3329) {
        _inlineMlKemPairs(b2, aHat, bPoly, ntt.gammas);
      } else {
        _inlinePointwise(b2, aHat, bPoly, q);
      }
    }, b2);
  }

  if (q == 8380417) {
    final am = aMont!;
    final bm = bMont!;
    runArm('redc2PW', () {
      _redc2Into(destInl.coeffs, am, bm);
    }, destInl);
  }

  for (final MapEntry(key: name, value: ns) in arms.entries) {
    _reportArm(ringName, name, ns, rounds);
  }

  // Projections (within-session pairing) ------------------------------------

  double med(String key) {
    final sorted = List<double>.from(arms[key]!)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length % 2 == 0
        ? (sorted[mid - 1] + sorted[mid]) / 2.0
        : sorted[mid];
  }

  final pf = med('prodF');
  final ff = med('fusedF');
  final pi = med('prodI');
  final fi = med('fusedI');
  final pb = med('prodB');
  final ib = med('inlineB');

  final fwdPct = (ff - pf) / pf * 100.0;
  final pairProd = pf + pi;
  final pairFused = ff + fi;
  final pairPct = (pairFused - pairProd) / pairProd * 100.0;
  final pipeProd = 2 * pf + pi + pb;
  final pipeInline = 2 * ff + fi + ib;
  final pipePct = (pipeInline - pipeProd) / pipeProd * 100.0;

  stderr.writeln(
    'CONTEXT $ringName session prodF=${pf.toStringAsFixed(0)} ns '
    '(shipped fwd $shippedFwdNs ns) — session drift sanity',
  );
  stderr.writeln(
    'PROJ $ringName fwd ${fwdPct.toStringAsFixed(1)}% '
    'pair ${pairPct.toStringAsFixed(1)}% '
    'pipeline(fused+call-graph-inline) ${pipePct.toStringAsFixed(1)}% '
    '(session est ${pipeInline.toStringAsFixed(0)} ns vs shipped '
    '$shippedPipelineNs ns)',
  );

  if (q == 8380417) {
    final rb = med('redc2PW');
    final pipeRedc2 = 2 * ff + fi + rb;
    final pipeRedc2Pct = (pipeRedc2 - pipeProd) / pipeProd * 100.0;
    stderr.writeln(
      'PROJ $ringName pipeline(fused+redc2-pointwise) '
      '${pipeRedc2Pct.toStringAsFixed(1)}% '
      '(session est ${pipeRedc2.toStringAsFixed(0)} ns; requires '
      'Montgomery-domain basemul inputs)',
    );
  }

  final best = pipePct;
  final verdict = best <= -15.0
      ? 'GO (>=15%)'
      : best < -10.0
      ? 'MARGINAL (10-15%)'
      : 'NO-GO (<10% projected — cost model refuted, honest residual '
            'quantified)';
  stderr.writeln(
    'GATE $ringName: best pipeline projection '
    '${best.toStringAsFixed(1)}% -> $verdict',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Fused candidate kernels — direct twiddle indexing, exact shipped chains
// ─────────────────────────────────────────────────────────────────────────────

void _fusedFwd(NttParams ntt, List<int> a, {List<int>? zetasMont}) {
  final q = ntt.ring.q;
  if (q == 3329 && ntt.ring.n == 256) {
    _mlKemFusedFwd(ntt.zetas, a);
  } else if (q == 8380417 && ntt.ring.n == 256) {
    final zm =
        zetasMont ??
        ntt.zetas.map((z) => ModQ.toMont(z, MontgomeryParams.forQ(q))).toList();
    _mlDsaFusedFwd(zm, a);
  } else if (q == 12289) {
    _fnFusedFwd(ntt, a);
  } else {
    throw ArgumentError('O2 fused forward: unsupported ring ${ntt.ring}');
  }
}

void _fusedInv(
  NttParams ntt,
  List<int> a, {
  List<int>? zetasMont,
  int? invMont,
}) {
  final q = ntt.ring.q;
  if (q == 3329 && ntt.ring.n == 256) {
    _mlKemFusedInv(ntt.zetas, ntt.invNScale, a);
  } else if (q == 8380417 && ntt.ring.n == 256) {
    final zm =
        zetasMont ??
        ntt.zetas.map((z) => ModQ.toMont(z, MontgomeryParams.forQ(q))).toList();
    final im = invMont ?? ModQ.toMont(ntt.invNScale, MontgomeryParams.forQ(q));
    _mlDsaFusedInv(zm, im, a);
  } else if (q == 12289) {
    _fnFusedInv(ntt, a);
  } else {
    throw ArgumentError('O2 fused inverse: unsupported ring ${ntt.ring}');
  }
}

// ── ML-KEM: single-guard chain (v=20159/26), fused two-layer passes.
//
// Twiddle indexing (derived from the production block-major consumption
// order): a forward layer with len consumes 256/(2*len) zetas starting at
// index 256/(2*len); a fused super-block b covers len-blocks 2b, 2b+1 and the
// two len/2-blocks they contain. Inverse: layer len first index is
// 256/len - 1, descending.

void _mlKemFusedFwd(List<int> zetas, List<int> f) {
  const q = 3329;
  for (final (len, len2) in const [(128, 64), (32, 16), (8, 4)]) {
    final c = 256 ~/ (2 * len);
    for (var b = 0; b < c; b++) {
      final s = 2 * len * b;
      final zA = zetas[c + b];
      for (var j = s; j < s + len; j++) {
        final fj = f[j];
        final fjl = f[j + len];
        final raw = zA * fjl;
        final quot = (raw * 20159) >> 26;
        var t = raw - quot * q;
        if (t < 0 || t >= q) t %= q;
        final diff = fj - t;
        f[j + len] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        f[j] = sum >= q ? sum - q : sum;
      }
      final zB = zetas[2 * c + 2 * b];
      for (var j = s; j < s + len2; j++) {
        final fj = f[j];
        final fjl = f[j + len2];
        final raw = zB * fjl;
        final quot = (raw * 20159) >> 26;
        var t = raw - quot * q;
        if (t < 0 || t >= q) t %= q;
        final diff = fj - t;
        f[j + len2] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        f[j] = sum >= q ? sum - q : sum;
      }
      final zC = zetas[2 * c + 2 * b + 1];
      for (var j = s + len; j < s + len + len2; j++) {
        final fj = f[j];
        final fjl = f[j + len2];
        final raw = zC * fjl;
        final quot = (raw * 20159) >> 26;
        var t = raw - quot * q;
        if (t < 0 || t >= q) t %= q;
        final diff = fj - t;
        f[j + len2] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        f[j] = sum >= q ? sum - q : sum;
      }
    }
  }
  // Single final layer len=2: first index 64; 64 blocks of size 4.
  for (var b = 0; b < 64; b++) {
    final zeta = zetas[64 + b];
    final s = 4 * b;
    for (var j = s; j < s + 2; j++) {
      final fj = f[j];
      final fjl = f[j + 2];
      final raw = zeta * fjl;
      final quot = (raw * 20159) >> 26;
      var t = raw - quot * q;
      if (t < 0 || t >= q) t %= q;
      final diff = fj - t;
      f[j + 2] = diff < 0 ? diff + q : diff;
      final sum = fj + t;
      f[j] = sum >= q ? sum - q : sum;
    }
  }
}

void _mlKemFusedInv(List<int> zetas, int inv, List<int> f) {
  const q = 3329;
  for (final (lenA, lenB) in const [(2, 4), (8, 16), (32, 64)]) {
    final kb = 256 ~/ (2 * lenB);
    final kA = 256 ~/ lenA;
    for (var b = 0; b < kb; b++) {
      final s = 2 * lenB * b;
      final z1 = zetas[kA - 1 - 2 * b];
      for (var j = s; j < s + lenA; j++) {
        final t = f[j];
        final u = f[j + lenA];
        final sum = t + u;
        f[j] = sum >= q ? sum - q : sum;
        var diff = u - t;
        diff = diff < 0 ? diff + q : diff;
        final raw = z1 * diff;
        final quot = (raw * 20159) >> 26;
        var r2 = raw - quot * q;
        if (r2 < 0 || r2 >= q) r2 %= q;
        f[j + lenA] = r2;
      }
      final z2 = zetas[kA - 2 - 2 * b];
      for (var j = s + 2 * lenA; j < s + 3 * lenA; j++) {
        final t = f[j];
        final u = f[j + lenA];
        final sum = t + u;
        f[j] = sum >= q ? sum - q : sum;
        var diff = u - t;
        diff = diff < 0 ? diff + q : diff;
        final raw = z2 * diff;
        final quot = (raw * 20159) >> 26;
        var r2 = raw - quot * q;
        if (r2 < 0 || r2 >= q) r2 %= q;
        f[j + lenA] = r2;
      }
      final z3 = zetas[(256 ~/ lenB - 1) - b];
      for (var j = s; j < s + 2 * lenA; j++) {
        final t = f[j];
        final u = f[j + 2 * lenA];
        final sum = t + u;
        f[j] = sum >= q ? sum - q : sum;
        var diff = u - t;
        diff = diff < 0 ? diff + q : diff;
        final raw = z3 * diff;
        final quot = (raw * 20159) >> 26;
        var r2 = raw - quot * q;
        if (r2 < 0 || r2 >= q) r2 %= q;
        f[j + 2 * lenA] = r2;
      }
    }
  }
  // Single layer len=128: zeta = zetas[1]; 128 butterflies.
  final z = zetas[1];
  for (var j = 0; j < 128; j++) {
    final t = f[j];
    final u = f[j + 128];
    final sum = t + u;
    f[j] = sum >= q ? sum - q : sum;
    var diff = u - t;
    diff = diff < 0 ? diff + q : diff;
    final raw = z * diff;
    final quot = (raw * 20159) >> 26;
    var r2 = raw - quot * q;
    if (r2 < 0 || r2 >= q) r2 %= q;
    f[j + 128] = r2;
  }
  // Final scale.
  for (var i = 0; i < 256; i++) {
    final raw = f[i] * inv;
    final quot = (raw * 20159) >> 26;
    var r2 = raw - quot * q;
    if (r2 < 0 || r2 >= q) r2 %= q;
    f[i] = r2;
  }
}

// ── ML-DSA: 32-bit-word REDC with Montgomery-form twiddles, plain-domain.
// Twiddles arrive pre-converted (zetasMont[k] = zetas[k]*R mod q, built once
// by the caller); fused kernels index them directly, exactly like the
// production `_mlDsaForward`. The inverse conjugates per block (q - zetaM).

void _mlDsaFusedFwd(List<int> zetasMont, List<int> a) {
  const q = 8380417;
  const mask = 0xFFFFFFFF;
  const nPrime = 4236238847;
  for (final (len, len2) in const [(128, 64), (32, 16), (8, 4), (2, 1)]) {
    final c = 256 ~/ (2 * len);
    for (var b = 0; b < c; b++) {
      final s = 2 * len * b;
      final zA = zetasMont[c + b];
      for (var j = s; j < s + len; j++) {
        final prod = zA * a[j + len];
        final m = ((prod & mask) * nPrime) & mask;
        var t = (prod + m * q) >> 32;
        if (t >= q) t -= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
      final zB = zetasMont[2 * c + 2 * b];
      for (var j = s; j < s + len2; j++) {
        final prod = zB * a[j + len2];
        final m = ((prod & mask) * nPrime) & mask;
        var t = (prod + m * q) >> 32;
        if (t >= q) t -= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len2] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
      final zC = zetasMont[2 * c + 2 * b + 1];
      for (var j = s + len; j < s + len + len2; j++) {
        final prod = zC * a[j + len2];
        final m = ((prod & mask) * nPrime) & mask;
        var t = (prod + m * q) >> 32;
        if (t >= q) t -= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len2] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
    }
  }
}

void _mlDsaFusedInv(List<int> zetasMont, int invMont, List<int> a) {
  const q = 8380417;
  const mask = 0xFFFFFFFF;
  const nPrime = 4236238847;
  for (final (lenA, lenB) in const [(1, 2), (4, 8), (16, 32), (64, 128)]) {
    final kb = 256 ~/ (2 * lenB);
    final kA = 256 ~/ lenA;
    for (var b = 0; b < kb; b++) {
      final s = 2 * lenB * b;
      var z1 = zetasMont[kA - 1 - 2 * b];
      z1 = q - z1; // -zetas[k] in Montgomery form
      for (var j = s; j < s + lenA; j++) {
        final t = a[j];
        final u = a[j + lenA];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        var diff = t - u;
        diff = diff < 0 ? diff + q : diff;
        final prod = z1 * diff;
        final m = ((prod & mask) * nPrime) & mask;
        var rt = (prod + m * q) >> 32;
        if (rt >= q) rt -= q;
        a[j + lenA] = rt;
      }
      var z2 = zetasMont[kA - 2 - 2 * b];
      z2 = q - z2;
      for (var j = s + 2 * lenA; j < s + 3 * lenA; j++) {
        final t = a[j];
        final u = a[j + lenA];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        var diff = t - u;
        diff = diff < 0 ? diff + q : diff;
        final prod = z2 * diff;
        final m = ((prod & mask) * nPrime) & mask;
        var rt = (prod + m * q) >> 32;
        if (rt >= q) rt -= q;
        a[j + lenA] = rt;
      }
      var z3 = zetasMont[(256 ~/ lenB - 1) - b];
      z3 = q - z3;
      for (var j = s; j < s + 2 * lenA; j++) {
        final t = a[j];
        final u = a[j + 2 * lenA];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        var diff = t - u;
        diff = diff < 0 ? diff + q : diff;
        final prod = z3 * diff;
        final m = ((prod & mask) * nPrime) & mask;
        var rt = (prod + m * q) >> 32;
        if (rt >= q) rt -= q;
        a[j + 2 * lenA] = rt;
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    final prod = invMont * a[i];
    final m = ((prod & mask) * nPrime) & mask;
    var rt = (prod + m * q) >> 32;
    if (rt >= q) rt -= q;
    a[i] = rt;
  }
}

// ── FN-DSA: k=27 chain (mu=10921 = floor(2^27/12289)), fused two-layer
// passes, parametric n (512/1024). Indexing follows the same derivation as
// ML-KEM with zeta-first-index n/(2*len) forward and n/len - 1 inverse.

void _fnFusedFwd(NttParams ntt, List<int> a) {
  final zetas = ntt.zetas;
  final n = ntt.ring.n;
  const q = 12289;
  for (var len = n >> 1; len >= 2; len >>= 2) {
    final len2 = len >> 1;
    final c = n ~/ (2 * len);
    for (var b = 0; b < c; b++) {
      final s = 2 * len * b;
      final zA = zetas[c + b];
      for (var j = s; j < s + len; j++) {
        final raw = zA * a[j + len];
        final quot = (raw * 10921) >> 27;
        var t = raw - quot * q;
        t = t >= q ? t - q : t;
        t = t >= q ? t - q : t;
        if (t < 0) t += q;
        if (t >= q) t %= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
      final zB = zetas[2 * c + 2 * b];
      for (var j = s; j < s + len2; j++) {
        final raw = zB * a[j + len2];
        final quot = (raw * 10921) >> 27;
        var t = raw - quot * q;
        t = t >= q ? t - q : t;
        t = t >= q ? t - q : t;
        if (t < 0) t += q;
        if (t >= q) t %= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len2] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
      final zC = zetas[2 * c + 2 * b + 1];
      for (var j = s + len; j < s + len + len2; j++) {
        final raw = zC * a[j + len2];
        final quot = (raw * 10921) >> 27;
        var t = raw - quot * q;
        t = t >= q ? t - q : t;
        t = t >= q ? t - q : t;
        if (t < 0) t += q;
        if (t >= q) t %= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len2] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
    }
  }
  if (n == 512) {
    // Leftover single len=1 layer: 256 blocks of size 2, zetas[256 + b].
    for (var b = 0; b < 256; b++) {
      final zeta = zetas[256 + b];
      final s = 2 * b;
      final raw = zeta * a[s + 1];
      final quot = (raw * 10921) >> 27;
      var t = raw - quot * q;
      t = t >= q ? t - q : t;
      t = t >= q ? t - q : t;
      if (t < 0) t += q;
      if (t >= q) t %= q;
      final fj = a[s];
      final diff = fj - t;
      a[s + 1] = diff < 0 ? diff + q : diff;
      final sum = fj + t;
      a[s] = sum >= q ? sum - q : sum;
    }
  }
}

void _fnFusedInv(NttParams ntt, List<int> a) {
  final zetas = ntt.zetas;
  final n = ntt.ring.n;
  const q = 12289;
  for (var lenA = 1; lenA <= (n >> 2); lenA <<= 2) {
    final lenB = lenA << 1;
    final kb = n ~/ (2 * lenB);
    final kA = n ~/ lenA;
    for (var b = 0; b < kb; b++) {
      final s = 2 * lenB * b;
      var z1 = zetas[kA - 1 - 2 * b];
      z1 = q - z1; // -zeta
      for (var j = s; j < s + lenA; j++) {
        final t = a[j];
        final u = a[j + lenA];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        var diff = t - u;
        diff = diff < 0 ? diff + q : diff;
        final raw = diff * z1;
        final quot = (raw * 10921) >> 27;
        var r = raw - quot * q;
        r = r >= q ? r - q : r;
        r = r >= q ? r - q : r;
        if (r < 0) r += q;
        if (r >= q) r %= q;
        a[j + lenA] = r;
      }
      var z2 = zetas[kA - 2 - 2 * b];
      z2 = q - z2;
      for (var j = s + 2 * lenA; j < s + 3 * lenA; j++) {
        final t = a[j];
        final u = a[j + lenA];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        var diff = t - u;
        diff = diff < 0 ? diff + q : diff;
        final raw = diff * z2;
        final quot = (raw * 10921) >> 27;
        var r = raw - quot * q;
        r = r >= q ? r - q : r;
        r = r >= q ? r - q : r;
        if (r < 0) r += q;
        if (r >= q) r %= q;
        a[j + lenA] = r;
      }
      var z3 = zetas[(n ~/ lenB - 1) - b];
      z3 = q - z3;
      for (var j = s; j < s + 2 * lenA; j++) {
        final t = a[j];
        final u = a[j + 2 * lenA];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        var diff = t - u;
        diff = diff < 0 ? diff + q : diff;
        final raw = diff * z3;
        final quot = (raw * 10921) >> 27;
        var r = raw - quot * q;
        r = r >= q ? r - q : r;
        r = r >= q ? r - q : r;
        if (r < 0) r += q;
        if (r >= q) r %= q;
        a[j + 2 * lenA] = r;
      }
    }
  }
  if (n == 512) {
    // Leftover single len=256 layer: conjugate zetas[1], 256 pairs.
    var z = zetas[1];
    z = q - z;
    for (var j = 0; j < 256; j++) {
      final t = a[j];
      final u = a[j + 256];
      final sum = t + u;
      a[j] = sum >= q ? sum - q : sum;
      var diff = t - u;
      diff = diff < 0 ? diff + q : diff;
      final raw = diff * z;
      final quot = (raw * 10921) >> 27;
      var r = raw - quot * q;
      r = r >= q ? r - q : r;
      r = r >= q ? r - q : r;
      if (r < 0) r += q;
      if (r >= q) r %= q;
      a[j + 256] = r;
    }
  }
  // Final scale (plain inv, no conjugate).
  final inv = ntt.invNScale;
  for (var i = 0; i < n; i++) {
    final c = a[i];
    final raw = c * inv;
    final quot = (raw * 10921) >> 27;
    var r = raw - quot * q;
    r = r >= q ? r - q : r;
    r = r >= q ? r - q : r;
    if (r < 0) r += q;
    if (r >= q) r %= q;
    a[i] = r;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Basemul call-graph-removal candidate kernels
// ─────────────────────────────────────────────────────────────────────────────

/// Call-graph-removal candidates below inline the exact shipped
/// `ModQ.reduceBarrett` recipe for products of two residues (raw >= 0 always
/// in this domain, so the negative-input branch is dead but value-identical;
/// the three csubq corrections, negative fix, and `%` escape are kept
/// verbatim). Recipes match `BarrettParams.forQ`:
/// (3329: mu=5039/sh=24), (12289: mu=1365/sh=24), (8380417: mu=33587228/sh=48).

// Inlined mlKemPairs with the shipped recipe and inline addFast — every
// ModQ call expanded (call-graph removal probe).
void _inlineMlKemPairs(Poly dest, Poly aHat, Poly bHat, List<int> gammas) {
  const q = 3329;
  const mu = 5039;
  const shift = 24;
  for (var i = 0; i < 256; i += 2) {
    final a0 = aHat.coeffs[i];
    final a1 = aHat.coeffs[i + 1];
    final b0 = bHat.coeffs[i];
    final b1 = bHat.coeffs[i + 1];
    final gamma = gammas[i >> 1];
    // t0 = chain(a0*b0)
    var raw = a0 * b0;
    var quot = (raw * mu) >> shift;
    var t0 = raw - quot * q;
    t0 = t0 >= q ? t0 - q : t0;
    t0 = t0 >= q ? t0 - q : t0;
    t0 = t0 >= q ? t0 - q : t0;
    if (t0 < 0) t0 += q;
    if (t0 >= q) t0 %= q;
    // t1 = chain(chain(a1*b1) * gamma)
    raw = a1 * b1;
    quot = (raw * mu) >> shift;
    var inner = raw - quot * q;
    inner = inner >= q ? inner - q : inner;
    inner = inner >= q ? inner - q : inner;
    inner = inner >= q ? inner - q : inner;
    if (inner < 0) inner += q;
    if (inner >= q) inner %= q;
    raw = inner * gamma;
    quot = (raw * mu) >> shift;
    var t1 = raw - quot * q;
    t1 = t1 >= q ? t1 - q : t1;
    t1 = t1 >= q ? t1 - q : t1;
    t1 = t1 >= q ? t1 - q : t1;
    if (t1 < 0) t1 += q;
    if (t1 >= q) t1 %= q;
    // dest[i] = addFast(t0, t1)
    var s = t0 + t1;
    dest.coeffs[i] = s >= q ? s - q : s;
    // m01 = chain(a0*b1), m10 = chain(a1*b0)
    raw = a0 * b1;
    quot = (raw * mu) >> shift;
    var m01 = raw - quot * q;
    m01 = m01 >= q ? m01 - q : m01;
    m01 = m01 >= q ? m01 - q : m01;
    m01 = m01 >= q ? m01 - q : m01;
    if (m01 < 0) m01 += q;
    if (m01 >= q) m01 %= q;
    raw = a1 * b0;
    quot = (raw * mu) >> shift;
    var m10 = raw - quot * q;
    m10 = m10 >= q ? m10 - q : m10;
    m10 = m10 >= q ? m10 - q : m10;
    m10 = m10 >= q ? m10 - q : m10;
    if (m10 < 0) m10 += q;
    if (m10 >= q) m10 %= q;
    s = m01 + m10;
    dest.coeffs[i + 1] = s >= q ? s - q : s;
  }
}

/// Inlined generic pointwise with the per-ring shipped recipe
/// (same chain shape as `ModQ.reduceBarrett`, calls removed).
void _inlinePointwise(Poly dest, Poly aHat, Poly bHat, int q) {
  int mu;
  int shift;
  switch (q) {
    case 3329:
      mu = 5039;
      shift = 24;
    case 12289:
      mu = 1365;
      shift = 24;
    case 8380417:
      mu = 33587228;
      shift = 48;
    default:
      throw ArgumentError('inline pointwise: unsupported q=$q');
  }
  for (var i = 0; i < dest.n; i++) {
    final raw = aHat.coeffs[i] * bHat.coeffs[i];
    final quot = (raw * mu) >> shift;
    var r = raw - quot * q;
    r = r >= q ? r - q : r;
    r = r >= q ? r - q : r;
    r = r >= q ? r - q : r;
    if (r < 0) r += q;
    if (r >= q) r %= q;
    dest.coeffs[i] = r;
  }
}

/// Wrap-free Montgomery pointwise candidate on plain-domain hats: inputs are
/// pre-converted to Montgomery form in setup; stage 1 REDC(aM*bM) =
/// (a*b)·R mod q; stage 2 REDC = (a*b) mod q. Two inline single-limb REDCs,
/// no wrap in int64 (prod < q^2 < 2^46; (prod + m*q) < 2^56), no division.
void _redc2Into(List<int> out, List<int> aM, List<int> bM) {
  const q = 8380417;
  const mask = 0xFFFFFFFF;
  const nPrime = 4236238847;
  for (var i = 0; i < out.length; i++) {
    final prod = aM[i] * bM[i];
    final m = ((prod & mask) * nPrime) & mask;
    var t = (prod + m * q) >> 32;
    if (t >= q) t -= q;
    final m2 = ((t & mask) * nPrime) & mask;
    var u = (t + m2 * q) >> 32;
    if (u >= q) u -= q;
    out[i] = u;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parity (before any timing)
// ─────────────────────────────────────────────────────────────────────────────

bool _runParity() {
  var ok = true;
  ok &= _parityRing(RingParams.mlKem, 'mlKem');
  ok &= _parityRing(RingParams.mlDsa, 'mlDsa');
  ok &= _parityRing(RingParams.fnDsa512, 'fnDsa512');
  ok &= _parityRing(RingParams.fnDsa1024, 'fnDsa1024');
  return ok;
}

bool _parityRing(RingParams ring, String name) {
  final engine = NttEngine(ring);
  final ntt = NttParams.forRing(ring);
  final q = ring.q;

  for (var pattern = 0; pattern < 2; pattern++) {
    final base = Poly.fromCoeffs(ring, _patternCoeffs(ring, pattern));

    // Production references.
    final refFwd = base.clone();
    engine.forwardInPlace(refFwd);
    final refPair = base.clone();
    engine.forwardInPlace(refPair);
    engine.inverseInPlace(refPair);

    // Fused forward-only.
    final fusedF = base.clone();
    _fusedFwd(ntt, fusedF.coeffs);
    for (var i = 0; i < ring.n; i++) {
      if (fusedF.coeffs[i] != refFwd.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/fusedFwd p$pattern: coeff $i = ${fusedF.coeffs[i]} '
          'expected ${refFwd.coeffs[i]}',
        );
        return false;
      }
    }

    // Fused pair.
    final fusedP = base.clone();
    _fusedFwd(ntt, fusedP.coeffs);
    _fusedInv(ntt, fusedP.coeffs);
    for (var i = 0; i < ring.n; i++) {
      if (fusedP.coeffs[i] != refPair.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/fusedPair p$pattern: coeff $i = ${fusedP.coeffs[i]} '
          'expected ${refPair.coeffs[i]}',
        );
        return false;
      }
    }

    // Basemul arms.
    final aHat = base.clone();
    engine.forwardInPlace(aHat);
    final bPoly = Poly.fromCoeffs(ring, _patternCoeffs(ring, pattern + 1));
    engine.forwardInPlace(bPoly);

    final destProd = Poly.zero(ring);
    final destInl = Poly.zero(ring);
    if (q == 3329) {
      Basemul.mlKemPairsInPlace(destProd, aHat, bPoly);
      _inlineMlKemPairs(destInl, aHat, bPoly, ntt.gammas);
    } else {
      Basemul.pointwiseInPlace(destProd, aHat, bPoly, ring);
      _inlinePointwise(destInl, aHat, bPoly, q);
    }
    for (var i = 0; i < ring.n; i++) {
      if (destProd.coeffs[i] != destInl.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/inlineBasemul p$pattern: coeff $i = '
          '${destInl.coeffs[i]} expected ${destProd.coeffs[i]}',
        );
        return false;
      }
    }

    if (q == 8380417) {
      final mont = MontgomeryParams.forQ(q);
      final am = aHat.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
      final bm = bPoly.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
      final redc2 = List<int>.filled(ring.n, 0);
      _redc2Into(redc2, am, bm);
      for (var i = 0; i < ring.n; i++) {
        if (redc2[i] != destProd.coeffs[i]) {
          stderr.writeln(
            'PARITY $name/redc2 p$pattern: coeff $i = ${redc2[i]} '
            'expected ${destProd.coeffs[i]}',
          );
          return false;
        }
      }
    }
  }
  stderr.writeln(
    'PARITY $name: fused fwd/pair + basemul candidates OK (both patterns)',
  );
  return true;
}

/// Deterministic coefficient patterns: 0 = (i*17+3)%q bench pattern;
/// 1 = LCG stream with a fixed seed (different from any other fixture).
List<int> _patternCoeffs(RingParams ring, int mode) {
  final out = List<int>.filled(ring.n, 0);
  var x = 0x5EED1234;
  for (var i = 0; i < ring.n; i++) {
    if (mode == 0) {
      out[i] = (i * 17 + 3) % ring.q;
    } else {
      x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
      out[i] = x % ring.q;
    }
  }
  return out;
}

/// Deterministic poly with coefficients in [0, q) (LCG, fixed seed per ring).
Poly _benchPoly(RingParams ring, int seed) {
  final rnd = Random(seed);
  return Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
}

/// TSV row for one arm.
void _reportArm(String ring, String arm, List<double> ns, int rounds) {
  final sorted = List<double>.from(ns)..sort();
  final mid = sorted.length ~/ 2;
  final median = sorted.length % 2 == 0
      ? (sorted[mid - 1] + sorted[mid]) / 2.0
      : sorted[mid];
  final mean = ns.fold(0.0, (a, b) => a + b) / ns.length;
  final minV = sorted.first;
  final maxV = sorted.last;
  var sq = 0.0;
  for (final v in ns) {
    sq += (v - mean) * (v - mean);
  }
  final sd = sqrt(sq / ns.length);
  final rstd = mean == 0 ? 0.0 : sd / mean * 100.0;
  print(
    '$ring\t$arm\t${median.toStringAsFixed(1)}\t${mean.toStringAsFixed(1)}'
    '\t${minV.toStringAsFixed(1)}\t${maxV.toStringAsFixed(1)}'
    '\t${rstd.toStringAsFixed(2)}\t$rounds',
  );
}
