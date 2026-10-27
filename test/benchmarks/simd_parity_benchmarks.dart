/// SIMD parity benchmark suite.
///
/// Measures SIMD-shaped pointwise vs scalar Barrett pointwise timing for
/// every shipped profile. This measures **speed only**, not correctness —
/// correctness parity is enforced by test/simd_pointwise_parity_test.dart
/// and is a merge gate independent of timing.
library;

import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:pqlattice/src/simd/ntt_simd_int32x4.dart';

import 'benchmark_harness.dart';

/// Runs all SIMD parity benchmarks and appends results to [out].
List<BenchmarkResult> runSimdParityBenchmarks({
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
    results.add(_benchScalarPointwise(ring, name, ctx, buildMode));
    results.add(_benchSimdPointwise(ring, name, ctx, buildMode));
  }

  drainBenchmarkSink();
  return results;
}

BenchmarkResult _benchScalarPointwise(
    RingParams ring, String name, BenchmarkContext ctx, String buildMode) {
  final rnd = Random(0x1753 ^ ring.q);
  final a = Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
  final b = Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
  var blackHole = 0;

  final ns = measureRounds(
    () {
      final c = Basemul.pointwise(a, b, ring);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'simd',
    operation: 'pointwise',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'optimizedScalar',
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

BenchmarkResult _benchSimdPointwise(
    RingParams ring, String name, BenchmarkContext ctx, String buildMode) {
  final rnd = Random(0xBEEF ^ ring.q);
  final a = Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
  final b = Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
  final out = Poly.zero(ring);
  var blackHole = 0;

  final ns = measureRounds(
    () {
      NttSimdInt32x4.pointwiseInPlace(out, a, b, ring);
      blackHole += out.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'simd',
    operation: 'pointwise',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'simd',
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
