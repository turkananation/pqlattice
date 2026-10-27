/// PolyVec / PolyMat benchmark suite.
///
/// Measures vector and matrix operations over polynomials:
/// - PolyVec construction, clone, indexing
/// - PolyMat construction, at(), setAt()
/// - Per-poly forward NTT on a PolyVec (forwardVec)
/// All inputs are deterministic fixed-seed polys; timing excludes setup.
library;

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs all PolyVec / PolyMat benchmarks and appends results to [out].
List<BenchmarkResult> runPolyVecBenchmarks({
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
    results.add(_benchPolyVecConstruct(ring, name, ctx, buildMode));
    results.add(_benchPolyVecClone(ring, name, ctx, buildMode));
    results.add(_benchPolyVecIndexing(ring, name, ctx, buildMode));
    results.add(_benchPolyMatConstruct(ring, name, ctx, buildMode));
    results.add(_benchPolyMatAtSetAt(ring, name, ctx, buildMode));
    results.add(_benchPolyVecForwardVec(ring, name, ctx, buildMode));
  }

  drainBenchmarkSink();
  return results;
}

// ── Private helpers ──────────────────────────────────────────────────

BenchmarkResult _benchPolyVecConstruct(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final k = ring.n ~/ 4; // vector length scaled to ring size
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final v = PolyVec.zero(ring, k);
      blackHole += v.length;
      observeInt(blackHole);
    },
    iterations: 1000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'polyvec',
    operation: 'construct',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 1000,
    rounds: 5,
    warmupIterations: 200,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}

BenchmarkResult _benchPolyVecClone(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final k = ring.n ~/ 4;
  final source = PolyVec.zero(ring, k);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final v = source.clone();
      blackHole += v.length;
      observeInt(blackHole);
    },
    iterations: 1000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'polyvec',
    operation: 'clone',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 1000,
    rounds: 5,
    warmupIterations: 200,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}

BenchmarkResult _benchPolyVecIndexing(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final k = ring.n ~/ 4;
  final v = PolyVec.zero(ring, k);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      for (var i = 0; i < k; i++) {
        blackHole += v[i].coeffs[0];
      }
      observeInt(blackHole);
    },
    iterations: 1000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'polyvec',
    operation: 'indexing',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 1000,
    rounds: 5,
    warmupIterations: 200,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}

BenchmarkResult _benchPolyMatConstruct(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rows = 4;
  final cols = 4;
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final m = PolyMat.zero(ring, rows, cols);
      blackHole += m.rows * m.cols;
      observeInt(blackHole);
    },
    iterations: 1000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'polymat',
    operation: 'construct',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 1000,
    rounds: 5,
    warmupIterations: 200,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}

BenchmarkResult _benchPolyMatAtSetAt(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rows = 4;
  final cols = 4;
  final m = PolyMat.zero(ring, rows, cols);
  final p = benchPoly(ring, 0x1753);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          m.setAt(r, c, p);
          blackHole += m.at(r, c).coeffs[0];
        }
      }
      observeInt(blackHole);
    },
    iterations: 1000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'polymat',
    operation: 'atSetAt',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 1000,
    rounds: 5,
    warmupIterations: 200,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}

BenchmarkResult _benchPolyVecForwardVec(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final k = ring.n ~/ 4;
  final engine = NttEngine(ring);
  final polys = List<Poly>.generate(k, (_) => benchPoly(ring, 0xBEEF));
  final vec = PolyVec.fromPolys(ring, polys);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final out = engine.forwardVec(vec);
      for (var i = 0; i < k; i++) {
        blackHole += out[i].coeffs[0];
      }
      observeInt(blackHole);
    },
    iterations: 1000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'polyvec',
    operation: 'forwardVec',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'accelerated',
    reduceStrategy: 'barrett',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 1000,
    rounds: 5,
    warmupIterations: 200,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}
