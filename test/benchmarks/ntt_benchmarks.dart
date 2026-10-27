/// NTT benchmark suite.
///
/// Measures forward, inverse, and forward+inverse for every shipped
/// profile, in both allocating and in-place layouts, under the default
/// accelerated kernel (Barrett reduce). Montgomery-domain variants are
/// measured where the engine supports them.
///
/// All inputs are deterministic fixed-seed polys; timing excludes setup.
library;

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs all NTT benchmarks and appends results to [out].
List<BenchmarkResult> runNttBenchmarks({
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

    // ── Allocating forward / inverse ──
    results.add(_benchNttForwardAlloc(ring, name, ctx, buildMode));
    results.add(_benchNttInverseAlloc(ring, name, ctx, buildMode));
    results.add(_benchNttRoundtripAlloc(ring, name, ctx, buildMode));

    // ── In-place forward / inverse ──
    results.add(_benchNttForwardInPlace(ring, name, ctx, buildMode));
    results.add(_benchNttInverseInPlace(ring, name, ctx, buildMode));

    // ── Montgomery-domain variants (opt-in, not default) ──
    if (mont.isReady) {
      results.add(
        _benchNttMontgomeryForwardAlloc(ring, name, mont, ctx, buildMode),
      );
      results.add(
        _benchNttMontgomeryRoundtripAlloc(ring, name, mont, ctx, buildMode),
      );
    }
  }

  drainBenchmarkSink();
  return results;
}

// ── Private helpers ──────────────────────────────────────────────────

BenchmarkResult _benchNttForwardAlloc(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring);
  final a = benchPoly(ring, 0x1753);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final h = engine.forward(a);
      blackHole += h.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'forward',
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

BenchmarkResult _benchNttInverseAlloc(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring);
  final a = benchPoly(ring, 0xBEEF);
  final h = engine.forward(a); // setup: produce NTT-domain input
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final back = engine.inverse(h);
      blackHole += back.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'inverse',
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

BenchmarkResult _benchNttRoundtripAlloc(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring);
  final a = benchPoly(ring, 0xCAFE);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final back = engine.inverse(engine.forward(a));
      blackHole += back.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'forward+inverse',
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

BenchmarkResult _benchNttForwardInPlace(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final p = benchPoly(ring, 0xDEAD + blackHole);
      engine.forwardInPlace(p);
      blackHole += p.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'forwardInPlace',
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

BenchmarkResult _benchNttInverseInPlace(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final p = benchPoly(ring, 0xFEED + blackHole);
      engine.forwardInPlace(p);
      engine.inverseInPlace(p);
      blackHole += p.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'inverseInPlace',
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

BenchmarkResult _benchNttMontgomeryForwardAlloc(
  RingParams ring,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring, montgomeryParams: mont);
  final a = benchPoly(ring, 0x5EED);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final h = engine.forward(a);
      blackHole += h.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'forward',
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

BenchmarkResult _benchNttMontgomeryRoundtripAlloc(
  RingParams ring,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final engine = NttEngine(ring, montgomeryParams: mont);
  final a = benchPoly(ring, 0xC0FFEE);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final back = engine.inverse(engine.forward(a));
      blackHole += back.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'ntt',
    operation: 'forward+inverse',
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
