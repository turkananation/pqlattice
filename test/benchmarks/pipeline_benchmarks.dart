/// Full pipeline benchmark suite: NTT → basemul → inverse NTT.
///
/// Measures the complete multiplication pipeline for every shipped
/// profile, in both allocating and in-place layouts, under both plain
/// (Barrett) and Montgomery domains where applicable.
///
/// This is the end-to-end measurement most relevant to scheme-layer
/// consumers. All inputs are deterministic fixed-seed polys; timing
/// excludes setup.
library;

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs all pipeline benchmarks and appends results to [out].
List<BenchmarkResult> runPipelineBenchmarks({
  required BenchmarkContext ctx,
  required String buildMode,
}) {
  final results = <BenchmarkResult>[];

  final profiles = <(RingParams, String)>[
    (RingParams.mlKem, 'mlKem'),
    (RingParams.mlDsa, 'mlDsa'),
    (RingParams.fnDsa512, 'fnDsa512'),
    (RingParams.fnDsa1024, 'fnDsa1024'),
  ];

  for (final (ring, name) in profiles) {
    final mont = MontgomeryParams.forQ(ring.q);

    // ── Plain (Barrett) pipeline ──
    results.add(_benchPipelineAllocPlain(ring, name, ctx, buildMode));
    results.add(_benchPipelineInPlacePlain(ring, name, ctx, buildMode));

    // ── Montgomery pipeline ──
    if (mont.isReady) {
      results.add(
        _benchPipelineAllocMontgomery(ring, name, mont, ctx, buildMode),
      );
      results.add(
        _benchPipelineInPlaceMontgomery(ring, name, mont, ctx, buildMode),
      );
    }
  }

  drainBenchmarkSink();
  return results;
}

// ── Private helpers ──────────────────────────────────────────────────

BenchmarkResult _benchPipelineAllocPlain(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring);
  final a = benchPoly(ring, 0x1753);
  final b = benchPoly(ring, 0xBEEF);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final cHat = ring.q == 3329 && ring.n == 256
          ? Basemul.mlKemPairs(engine.forward(a), engine.forward(b), ring)
          : Basemul.pointwise(engine.forward(a), engine.forward(b), ring);
      final c = engine.inverse(cHat);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'pipeline',
    operation: 'ntt+basemul+inv',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
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
  );
}

BenchmarkResult _benchPipelineInPlacePlain(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final x = benchPoly(ring, 0xCAFE + blackHole);
      final y = benchPoly(ring, 0xDEAD + blackHole);
      final engine = NttEngine(ring);
      engine.forwardInPlace(x);
      engine.forwardInPlace(y);
      if (ring.q == 3329 && ring.n == 256) {
        Basemul.mlKemPairsInPlace(x, x, y);
      } else {
        Basemul.pointwiseInPlace(x, x, y, ring);
      }
      engine.inverseInPlace(x);
      blackHole += x.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'pipeline',
    operation: 'ntt+basemul+inv',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'inPlace',
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
  );
}

// ── Montgomery pipeline ─────────────────────────────────────────────

BenchmarkResult _benchPipelineAllocMontgomery(
  RingParams ring,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring, montgomeryParams: mont);
  final a = benchPoly(ring, 0x1753);
  final b = benchPoly(ring, 0xBEEF);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final cHat = ring.q == 3329 && ring.n == 256
          ? Basemul.mlKemPairsMontgomery(
              engine.forward(a),
              engine.forward(b),
              mont,
            )
          : Basemul.pointwiseMontgomery(
              engine.forward(a),
              engine.forward(b),
              ring,
              mont,
            );
      final c = engine.inverse(cHat);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'pipeline',
    operation: 'ntt+basemul+inv',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'montgomery',
    layout: 'allocating',
    domain: 'montgomery',
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
  );
}

BenchmarkResult _benchPipelineInPlaceMontgomery(
  RingParams ring,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final x = benchPoly(ring, 0xCAFE + blackHole);
      final y = benchPoly(ring, 0xDEAD + blackHole);
      final engine = NttEngine(ring, montgomeryParams: mont);
      engine.forwardInPlace(x);
      engine.forwardInPlace(y);
      if (ring.q == 3329 && ring.n == 256) {
        Basemul.mlKemPairsMontgomeryInPlace(x, x, y, mont);
      } else {
        Basemul.pointwiseMontgomeryInPlace(x, x, y, ring, mont);
      }
      engine.inverseInPlace(x);
      blackHole += x.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'pipeline',
    operation: 'ntt+basemul+inv',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'montgomery',
    layout: 'inPlace',
    domain: 'montgomery',
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
  );
}
