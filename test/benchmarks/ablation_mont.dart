/// Stage-Mont attribution ablation: the opt-in Montgomery-domain pipeline
/// measured end-to-end against the shipped accelerated default.
///
/// The deferred Montgomery stage is already present as production scaffold:
/// `NttEngine` accepts `montgomeryParams`, and `Basemul` exposes
/// Montgomery-domain pointwise / ML-KEM pair products. This harness measures
/// that composition per ring with the same discipline as `ablation_o2.dart`
/// (no production file is touched):
///
/// - `montF` — engine forward with Montgomery parameters: converts the input
///   plain polynomial on entry, keeps the result in Montgomery domain.
///   Entry conversion is part of the arm (honest caller-visible cost).
/// - `montI` — engine inverse with Montgomery parameters: takes a
///   Montgomery-domain NTT hat, converts back to plain on exit.
/// - `montPW` — Montgomery-domain pointwise (`Basemul.pointwiseMontgomery`
///   or `mlKemPairsMontgomeryInPlace` on ML-KEM). Montgomery-domain hats are
///   pre-converted in setup, so the arm isolates the mul primitive (same
///   convention as the `redc2PW` arm in the O2 record).
/// - `montPipe` — the full deferred-stage chain in one arm:
///   forward(a) + forward(b) + pointwise + inverse, with all boundary
///   conversions included. This is the adoptable number: what a caller
///   gets today when wiring the Montgomery profile end to end.
/// - `prodF`/`prodI`/`prodB` — shipped accelerated arms (in-session pairing
///   reference), identical bodies to the O2 record.
/// - `redc2PW` (ML-DSA) — O2 anchor arm ported verbatim for continuity.
///
/// Parity: every Montgomery arm is checked coefficient-exact against the
/// shipped engine before any timing, over two deterministic input patterns,
/// including the full-pipeline and per-op conversions:
///
/// - `REDC(montFhat) == prodF(base)` (forward transform parity)
/// - `montI(baseHatMont as mont.forward output) == base` (inverse parity)
/// - `REDC(montPW output) == prodB output` (pointwise parity, per profile)
/// - `montPipe(a, b) == shipped pipeline product` (chain parity)
///
/// Output: TSV rows on stdout (ring/arm per-iteration ns); parity, per-op
/// and projection lines plus the gate verdict on stderr. Gate reads the
/// within-session paired projection: <= -15% pipeline -> build; > -10% ->
///
/// stop (refuted), matching the campaign adopt bar.
///
/// Usage:
///   dart compile exe test/benchmarks/ablation_mont.dart -o `<binary>`
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
          'Usage: ablation_mont.dart [--rounds N] [--iters N] [--skip-timing]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }

  final ok = _runParity();
  if (!ok) {
    stderr.writeln(
      'ABORT: parity failure — a Montgomery-stage candidate is wrong.',
    );
    exit(1);
  }
  stderr.writeln(
    'PARITY: all Montgomery-stage arms match production output '
    '(transform, pointwise and full chain, two input patterns).',
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
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  _runRing(
    ring: RingParams.mlDsa,
    ringName: 'mlDsa',
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  _runRing(
    ring: RingParams.fnDsa512,
    ringName: 'fnDsa512',
    rounds: rounds,
    iters: iters,
    warmup: warmup,
  );

  _runRing(
    ring: RingParams.fnDsa1024,
    ringName: 'fnDsa1024',
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
// Per-ring runner: shipped arms, Montgomery arms, projections + gate
// ─────────────────────────────────────────────────────────────────────────────

void _runRing({
  required RingParams ring,
  required String ringName,
  required int rounds,
  required int iters,
  required int warmup,
}) {
  final engine = NttEngine(ring);
  final montEngine = NttEngine(
    ring,
    montgomeryParams: MontgomeryParams.forQ(ring.q),
  );
  final mont = MontgomeryParams.forQ(ring.q);
  final base = _benchPoly(ring, 0x2BEEF5 ^ ring.q);
  final q = ring.q;

  // Setup lanes (mirrors the O2 layout so projections pair within-session).
  final baseFwdProd = base.clone();
  engine.forwardInPlace(baseFwdProd);

  // Montgomery forward of the base poly: plain -> Montgomery hat.
  // Kept in setup: it is the input lane for the priced inverse arm, and it
  // must NOT be rebuilt inside a timed arm.
  final baseFwdMont = base.clone();
  montEngine.forwardInPlace(baseFwdMont);

  // Basemul lanes: NTT-domain a/b hats (plain + Montgomery forms).
  final aHat = base.clone();
  engine.forwardInPlace(aHat);
  final bPoly = Poly.fromCoeffs(ring, _patternCoeffs(ring, 1));
  final bHat = bPoly.clone();
  engine.forwardInPlace(bHat);

  final aHatMont = base.clone();
  montEngine.forwardInPlace(aHatMont);
  final bHatMont = bPoly.clone();
  montEngine.forwardInPlace(bHatMont);

  final destProd = Poly.zero(ring);
  final destMont = Poly.zero(ring);

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

  // Shipped arms (O2 bodies, verbatim semantics).
  {
    final p = Poly.zero(ring);
    runArm('prodF', () {
      p.coeffs.setAll(0, base.coeffs);
      engine.forwardInPlace(p);
    }, p);

    final p3 = Poly.zero(ring);
    runArm('prodI', () {
      p3.coeffs.setAll(0, baseFwdProd.coeffs);
      engine.inverseInPlace(p3);
    }, p3);

    final b1 = destProd;
    runArm('prodB', () {
      if (q == 3329) {
        Basemul.mlKemPairsInPlace(b1, aHat, bHat);
      } else {
        Basemul.pointwiseInPlace(b1, aHat, bHat, ring);
      }
    }, b1);
  }

  // Montgomery arms.
  {
    final mf = Poly.zero(ring);
    runArm('montF', () {
      mf.coeffs.setAll(0, base.coeffs);
      montEngine.forwardInPlace(mf);
    }, mf);

    final mi = Poly.zero(ring);
    runArm('montI', () {
      mi.coeffs.setAll(0, baseFwdMont.coeffs);
      montEngine.inverseInPlace(mi);
    }, mi);

    final mp = destMont;
    runArm('montPW', () {
      if (q == 3329) {
        Basemul.mlKemPairsMontgomeryInPlace(mp, aHatMont, bHatMont, mont);
      } else {
        Basemul.pointwiseMontgomeryInPlace(mp, aHatMont, bHatMont, ring, mont);
      }
    }, mp);

    // Full deferred-stage chain: all boundary conversions included
    // (forward entry conversion, inverse exit conversion).
    final chA = Poly.zero(ring);
    final chB = Poly.zero(ring);
    final chD = Poly.zero(ring);
    runArm('montPipe', () {
      chA.coeffs.setAll(0, base.coeffs);
      chB.coeffs.setAll(0, bPoly.coeffs);
      montEngine.forwardInPlace(chA);
      montEngine.forwardInPlace(chB);
      if (q == 3329) {
        Basemul.mlKemPairsMontgomeryInPlace(chD, chA, chB, mont);
      } else {
        Basemul.pointwiseMontgomeryInPlace(chD, chA, chB, ring, mont);
      }
      montEngine.inverseInPlace(chD);
    }, chD);

    if (q == 8380417) {
      final am = aHat.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
      final bm = bHat.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
      runArm('redc2PW', () {
        _redc2Into(chD.coeffs, am, bm);
      }, chD);
    }
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
  final pi = med('prodI');
  final pb = med('prodB');
  final mF = med('montF');
  final mI = med('montI');
  final mPW = med('montPW');
  final mPipe = med('montPipe');

  final pipeShipped = 2 * pf + pi + pb;
  final pipePct = (mPipe - pipeShipped) / pipeShipped * 100.0;

  final fwdRatio = mF / pf;
  final invRatio = mI / pi;
  final pwRatio = mPW / pb;

  stderr.writeln(
    'CONTEXT $ringName session prodF=${pf.toStringAsFixed(0)} ns '
    '(in-session pairing anchor)',
  );
  stderr.writeln(
    'PEROP $ringName montF/prodF=${fwdRatio.toStringAsFixed(2)}x '
    'montI/prodI=${invRatio.toStringAsFixed(2)}x '
    'montPW/prodB=${pwRatio.toStringAsFixed(2)}x '
    '(>1 = slower than shipped)',
  );
  stderr.writeln(
    'PROJ $ringName pipeline(mont) ${pipePct.toStringAsFixed(1)}% '
    '(session est ${mPipe.toStringAsFixed(0)} ns vs shipped-composed '
    '${pipeShipped.toStringAsFixed(0)} ns)',
  );

  final verdict = pipePct <= -15.0
      ? 'GO (>=15%)'
      : pipePct < -10.0
      ? 'MARGINAL (10-15%)'
      : 'NO-GO (<10% projected — cost model refuted, honest residual '
            'quantified)';
  stderr.writeln(
    'GATE $ringName: mont pipeline projection '
    '${pipePct.toStringAsFixed(1)}% -> $verdict',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Montgomery pointwise anchor (O2 record continuity)
// ─────────────────────────────────────────────────────────────────────────────

/// Wrap-free Montgomery pointwise on plain-domain hats: inputs are
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
  final montEngine = NttEngine(
    ring,
    montgomeryParams: MontgomeryParams.forQ(ring.q),
  );
  final mont = MontgomeryParams.forQ(ring.q);
  final q = ring.q;
  final n = ring.n;

  for (var pattern = 0; pattern < 2; pattern++) {
    final base = Poly.fromCoeffs(ring, _patternCoeffs(ring, pattern));
    final bPoly = Poly.fromCoeffs(ring, _patternCoeffs(ring, pattern + 1));

    // Production references.
    final refFwd = base.clone();
    engine.forwardInPlace(refFwd);

    final refA = base.clone();
    engine.forwardInPlace(refA);
    final refB = bPoly.clone();
    engine.forwardInPlace(refB);
    final refProduct = Poly.zero(ring);
    if (q == 3329) {
      Basemul.mlKemPairsInPlace(refProduct, refA, refB);
    } else {
      Basemul.pointwiseInPlace(refProduct, refA, refB, ring);
    }
    engine.inverseInPlace(refProduct);

    // Montgomery forward parity: REDC(mont fwd output) == prodF output.
    final mf = base.clone();
    montEngine.forwardInPlace(mf);
    for (var i = 0; i < n; i++) {
      if (ModQ.fromMont(mf.coeffs[i], mont) != refFwd.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/montF p$pattern: coeff $i = '
          '${ModQ.fromMont(mf.coeffs[i], mont)} expected ${refFwd.coeffs[i]}',
        );
        return false;
      }
    }

    // Montgomery inverse parity: montI output == base (fwd then inv).
    final mi = mf.clone();
    montEngine.inverseInPlace(mi);
    for (var i = 0; i < n; i++) {
      if (mi.coeffs[i] != base.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/montI p$pattern: coeff $i = ${mi.coeffs[i]} '
          'expected ${base.coeffs[i]}',
        );
        return false;
      }
    }

    // Montgomery pointwise parity per profile.
    final mp = Poly.zero(ring);
    final aAkt = mf.clone(); // mont hat of base (fresh copy)
    final bMontHat = bPoly.clone();
    montEngine.forwardInPlace(bMontHat);
    if (q == 3329) {
      Basemul.mlKemPairsMontgomeryInPlace(mp, aAkt, bMontHat, mont);
    } else {
      Basemul.pointwiseMontgomeryInPlace(mp, aAkt, bMontHat, ring, mont);
    }
    final shippedProduct = Poly.zero(ring);
    if (q == 3329) {
      Basemul.mlKemPairsInPlace(shippedProduct, refA, refB);
    } else {
      Basemul.pointwiseInPlace(shippedProduct, refA, refB, ring);
    }
    for (var i = 0; i < n; i++) {
      if (ModQ.fromMont(mp.coeffs[i], mont) != shippedProduct.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/montPW p$pattern: coeff $i = '
          '${ModQ.fromMont(mp.coeffs[i], mont)} '
          'expected ${shippedProduct.coeffs[i]}',
        );
        return false;
      }
    }

    // Full chain parity: mont pipeline product == shipped pipeline product.
    final chA = base.clone();
    final chB = bPoly.clone();
    final chD = Poly.zero(ring);
    montEngine.forwardInPlace(chA);
    montEngine.forwardInPlace(chB);
    if (q == 3329) {
      Basemul.mlKemPairsMontgomeryInPlace(chD, chA, chB, mont);
    } else {
      Basemul.pointwiseMontgomeryInPlace(chD, chA, chB, ring, mont);
    }
    montEngine.inverseInPlace(chD);
    for (var i = 0; i < n; i++) {
      if (chD.coeffs[i] != refProduct.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/montPipe p$pattern: coeff $i = ${chD.coeffs[i]} '
          'expected ${refProduct.coeffs[i]}',
        );
        return false;
      }
    }

    // O2 anchor continuity (ML-DSA): redc2 == shipped basemul product.
    if (q == 8380417) {
      final am = refA.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
      final bm = refB.coeffs.map((c) => ModQ.toMont(c, mont)).toList();
      final redc2 = List<int>.filled(n, 0);
      _redc2Into(redc2, am, bm);
      for (var i = 0; i < n; i++) {
        if (redc2[i] != shippedProduct.coeffs[i]) {
          stderr.writeln(
            'PARITY $name/redc2 p$pattern: coeff $i = ${redc2[i]} '
            'expected ${shippedProduct.coeffs[i]}',
          );
          return false;
        }
      }
    }
  }
  stderr.writeln(
    'PARITY $name: mont transform/pointwise/chain arms OK (both patterns)',
  );
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic fixtures (O2 shapes, verbatim)
// ─────────────────────────────────────────────────────────────────────────────

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
