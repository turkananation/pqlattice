/// pqcrypto side-by-side benchmark and correctness test.
///
/// This is **the** interop test: it runs identical random polynomials through
/// pqcrypto's internal `Poly.ntt` / `Poly.baseMul` / `Poly.invNtt` and
/// pqlattice's `NttEngine.forward` / `Basemul.mlKemPairs` / `inverse`, and
/// asserts **bit-identical** results. It also benchmarks both pipelines
/// side-by-side so speed comparisons are evidence-based, not claimed.
///
/// Requires `pqcrypto` as a dev dependency (path: ../pqcrypto). On machines
/// where pqcrypto is not available, this suite is skipped.
library;

import 'dart:math';

import 'package:pqcrypto/src/algos/kyber/poly.dart' as pqcrypto;
import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs the pqcrypto side-by-side correctness and benchmark suite.
///
/// Returns a pair: [correctnessResults] (pass/fail per profile) and
/// [benchmarkResults] (timing for both libraries).
///
/// Throws [StateError] if pqcrypto is not available (e.g. on CI without the
/// sibling repo checked out).
(
  List<PqcryptoCorrectnessResult> correctnessResults,
  List<BenchmarkResult> benchmarkResults
) runPqcryptoSideBySide({
  required BenchmarkContext ctx,
  required String buildMode,
}) {
  final correctness = <PqcryptoCorrectnessResult>[];
  final benchmarks = <BenchmarkResult>[];

  // Only ML-KEM ring exists in pqcrypto's kyber Poly (q=3329, n=256).
  final ring = RingParams.mlKem;
  final engine = NttEngine(ring);

  // ── Correctness: bit-identical results across libraries ──
  final rnd = Random(0x1753);
  for (var trial = 0; trial < 20; trial++) {
    final coeffs = List<int>.generate(256, (_) => rnd.nextInt(3329));
    final a = Poly.fromCoeffs(ring, coeffs);
    final b = Poly.fromCoeffs(ring, List<int>.generate(256, (_) => rnd.nextInt(3329)));

    // ── pqcrypto pipeline ──
    final pa = pqcrypto.Poly(a.coeffs);
    final pb = pqcrypto.Poly(b.coeffs);
    final pAh = pqcrypto.Poly.ntt(pa);
    final pBh = pqcrypto.Poly.ntt(pb);
    final pCh = pqcrypto.Poly.baseMul(pAh, pBh);
    final pC = pqcrypto.Poly.invNtt(pCh);

    // ── pqlattice pipeline ──
    final aHat = engine.forward(a);
    final bHat = engine.forward(b);
    final cHat = Basemul.mlKemPairs(aHat, bHat, ring);
    final c = engine.inverse(cHat);

    var bitIdentical = true;
    for (var i = 0; i < 256; i++) {
      if (pC.coeffs[i] != c.coeffs[i]) {
        bitIdentical = false;
        break;
      }
    }

    correctness.add(PqcryptoCorrectnessResult(
      trial: trial,
      bitIdentical: bitIdentical,
      pqcryptoCoeff0: pC.coeffs[0],
      pqlatticeCoeff0: c.coeffs[0],
    ));

    if (!bitIdentical) {
      throw StateError(
        'pqcrypto side-by-side correctness FAILED at trial $trial: '
        'pqcrypto coeff[0]=${pC.coeffs[0]}, pqlattice coeff[0]=${c.coeffs[0]}',
      );
    }
  }

  // ── Benchmarks: pqcrypto vs pqlattice pipeline ──
  final aBench = Poly.fromCoeffs(
    ring,
    List<int>.generate(256, (i) => (i * 17 + 3) % 3329),
  );
  final bBench = Poly.fromCoeffs(
    ring,
    List<int>.generate(256, (i) => (i * 31 + 5) % 3329),
  );

  // pqcrypto full pipeline
  benchmarks.add(_benchPqcryptoPipeline(aBench, bBench, ctx, buildMode));

  // pqlattice full pipeline
  benchmarks.add(_benchPqlatticePipeline(engine, aBench, bBench, ctx, buildMode));

  // pqcrypto NTT only
  benchmarks.add(_benchPqcryptoNtt(aBench, ctx, buildMode));

  // pqlattice NTT only
  benchmarks.add(_benchPqlatticeNtt(engine, aBench, ctx, buildMode));

  // pqcrypto baseMul only (NTT-domain inputs)
  final pAhBench = pqcrypto.Poly.ntt(pqcrypto.Poly(aBench.coeffs));
  final pBhBench = pqcrypto.Poly.ntt(pqcrypto.Poly(bBench.coeffs));
  benchmarks.add(_benchPqcryptoBaseMul(pAhBench, pBhBench, ctx, buildMode));

  // pqlattice mlKemPairs only (NTT-domain inputs)
  final aHatBench = engine.forward(aBench);
  final bHatBench = engine.forward(bBench);
  benchmarks.add(_benchPqlatticeMlKemPairs(aHatBench, bHatBench, ring, ctx, buildMode));

  drainBenchmarkSink();
  return (correctness, benchmarks);
}

// ── Correctness result ─────────────────────────────────────────────────

/// Result of one correctness trial comparing pqcrypto vs pqlattice.
class PqcryptoCorrectnessResult {
  final int trial;
  final bool bitIdentical;
  final int pqcryptoCoeff0;
  final int pqlatticeCoeff0;

  PqcryptoCorrectnessResult({
    required this.trial,
    required this.bitIdentical,
    required this.pqcryptoCoeff0,
    required this.pqlatticeCoeff0,
  });
}

// ── pqcrypto pipeline benchmarks ───────────────────────────────────────

BenchmarkResult _benchPqcryptoPipeline(
  Poly a,
  Poly b,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final (ns, memoryDelta) = measureRounds(
    () {
      final pa = pqcrypto.Poly(a.coeffs);
      final pb = pqcrypto.Poly(b.coeffs);
      final pAh = pqcrypto.Poly.ntt(pa);
      final pBh = pqcrypto.Poly.ntt(pb);
      final pCh = pqcrypto.Poly.baseMul(pAh, pBh);
      final pC = pqcrypto.Poly.invNtt(pCh);
      blackHole += pC.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
    measureMemory: true,
  );

  return BenchmarkResult(
    suite: 'pqcrypto_side_by_side',
    operation: 'ntt+basemul+inv',
    profile: 'mlKem',
    q: 3329,
    n: 256,
    kernelMode: 'pqcrypto',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: kDefaultIterations,
    rounds: kDefaultRounds,
    warmupIterations: kDefaultWarmup,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
    memoryRssBytes: memoryDelta,
  );
}

BenchmarkResult _benchPqcryptoNtt(
  Poly a,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final (ns, memoryDelta) = measureRounds(
    () {
      final pa = pqcrypto.Poly(a.coeffs);
      final pAh = pqcrypto.Poly.ntt(pa);
      blackHole += pAh.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
    measureMemory: true,
  );

  return BenchmarkResult(
    suite: 'pqcrypto_side_by_side',
    operation: 'ntt',
    profile: 'mlKem',
    q: 3329,
    n: 256,
    kernelMode: 'pqcrypto',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: kDefaultIterations,
    rounds: kDefaultRounds,
    warmupIterations: kDefaultWarmup,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
    memoryRssBytes: memoryDelta,
  );
}

BenchmarkResult _benchPqcryptoBaseMul(
  pqcrypto.Poly aHat,
  pqcrypto.Poly bHat,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final (ns, memoryDelta) = measureRounds(
    () {
      final pCh = pqcrypto.Poly.baseMul(aHat, bHat);
      blackHole += pCh.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
    measureMemory: true,
  );

  return BenchmarkResult(
    suite: 'pqcrypto_side_by_side',
    operation: 'basemul',
    profile: 'mlKem',
    q: 3329,
    n: 256,
    kernelMode: 'pqcrypto',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'ntt',
    buildMode: buildMode,
    iterationsPerRound: kDefaultIterations,
    rounds: kDefaultRounds,
    warmupIterations: kDefaultWarmup,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
    memoryRssBytes: memoryDelta,
  );
}

// ── pqlattice pipeline benchmarks ──────────────────────────────────────

BenchmarkResult _benchPqlatticePipeline(
  NttEngine engine,
  Poly a,
  Poly b,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final (ns, memoryDelta) = measureRounds(
    () {
      final cHat = Basemul.mlKemPairs(engine.forward(a), engine.forward(b), ring);
      final c = engine.inverse(cHat);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
    measureMemory: true,
  );

  return BenchmarkResult(
    suite: 'pqcrypto_side_by_side',
    operation: 'ntt+basemul+inv',
    profile: 'mlKem',
    q: 3329,
    n: 256,
    kernelMode: 'pqlattice',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: kDefaultIterations,
    rounds: kDefaultRounds,
    warmupIterations: kDefaultWarmup,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
    memoryRssBytes: memoryDelta,
  );
}

BenchmarkResult _benchPqlatticeNtt(
  NttEngine engine,
  Poly a,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final (ns, memoryDelta) = measureRounds(
    () {
      final aHat = engine.forward(a);
      blackHole += aHat.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
    measureMemory: true,
  );

  return BenchmarkResult(
    suite: 'pqcrypto_side_by_side',
    operation: 'ntt',
    profile: 'mlKem',
    q: 3329,
    n: 256,
    kernelMode: 'pqlattice',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: kDefaultIterations,
    rounds: kDefaultRounds,
    warmupIterations: kDefaultWarmup,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
    memoryRssBytes: memoryDelta,
  );
}

BenchmarkResult _benchPqlatticeMlKemPairs(
  Poly aHat,
  Poly bHat,
  RingParams ring,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final (ns, memoryDelta) = measureRounds(
    () {
      final cHat = Basemul.mlKemPairs(aHat, bHat, ring);
      blackHole += cHat.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
    measureMemory: true,
  );

  return BenchmarkResult(
    suite: 'pqcrypto_side_by_side',
    operation: 'basemul',
    profile: 'mlKem',
    q: 3329,
    n: 256,
    kernelMode: 'pqlattice',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'ntt',
    buildMode: buildMode,
    iterationsPerRound: kDefaultIterations,
    rounds: kDefaultRounds,
    warmupIterations: kDefaultWarmup,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
    memoryRssBytes: memoryDelta,
  );
}

/// Ring used for ML-KEM side-by-side (q=3329, n=256).
final RingParams ring = RingParams.mlKem;
