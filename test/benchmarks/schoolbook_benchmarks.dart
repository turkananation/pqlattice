/// Schoolbook oracle benchmark suite.
///
/// Measures the negacyclic schoolbook product (RingMul.schoolbookNegacyclic)
/// — the L0 correctness oracle — across profiles and sizes. Provides the
/// baseline against which NTT-based multiplication is compared.
///
/// All inputs are deterministic fixed-seed polys; timing excludes setup.
library;

import 'dart:math';

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs all schoolbook benchmarks and appends results to [out].
List<BenchmarkResult> runSchoolbookBenchmarks({
  required BenchmarkContext ctx,
  required String buildMode,
}) {
  final results = <BenchmarkResult>[];

  // ── Toy rings for small-n exhaustive-style baseline ──
  final toyRings = <(RingParams, String)>[
    (RingParams(q: 17, n: 4, name: 'toy17n4'), 'toy17n4'),
    (RingParams(q: 17, n: 8, name: 'toy17n8'), 'toy17n8'),
    (RingParams(q: 17, n: 16, name: 'toy17n16'), 'toy17n16'),
  ];

  for (final (ring, name) in toyRings) {
    results.add(_benchSchoolbookToy(ring, name, ctx, buildMode));
  }

  // ── FIPS profiles at full size ──
  final fipsRings = <(RingParams, String)>[
    (RingParams.mlKem, 'mlKem'),
    (RingParams.mlDsa, 'mlDsa'),
    (RingParams.fnDsa512, 'fnDsa512'),
    (RingParams.fnDsa1024, 'fnDsa1024'),
  ];

  for (final (ring, name) in fipsRings) {
    results.add(_benchSchoolbookFips(ring, name, ctx, buildMode));
  }

  drainBenchmarkSink();
  return results;
}

// ── Private helpers ──────────────────────────────────────────────────

BenchmarkResult _benchSchoolbookToy(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
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
      final c = RingMul.schoolbookNegacyclic(a, b, ring);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: 2000,
    rounds: 5,
    warmup: 200,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'schoolbook',
    operation: 'schoolbookNegacyclic',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'reference',
    reduceStrategy: 'percent',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 2000,
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

BenchmarkResult _benchSchoolbookFips(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rnd = Random(0xBEEF ^ ring.q);
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
      final c = RingMul.schoolbookNegacyclic(a, b, ring);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: 100,
    rounds: 5,
    warmup: 50,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'schoolbook',
    operation: 'schoolbookNegacyclic',
    profile: name,
    q: ring.q,
    n: ring.n,
    kernelMode: 'reference',
    reduceStrategy: 'percent',
    layout: 'allocating',
    domain: 'plain',
    buildMode: buildMode,
    iterationsPerRound: 100,
    rounds: 5,
    warmupIterations: 50,
    roundNs: ns,
    sink: drainBenchmarkSink(),
    sdkVersion: ctx.sdkVersion,
    os: ctx.os,
    cpuCount: ctx.cpuCount,
    gitSha: ctx.gitSha,
  );
}
