/// Modular reduction benchmark suite.
///
/// Measures Barrett reduction vs the `%` reference, and Montgomery
/// `montMul`/`montReduce`, for every ready modulus. All inputs are
/// deterministic fixed-seed products in [0, q^2]; timing excludes setup.
library;

import 'dart:math';

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs all reduce benchmarks and appends results to [out].
List<BenchmarkResult> runReduceBenchmarks({
  required BenchmarkContext ctx,
  required String buildMode,
}) {
  final results = <BenchmarkResult>[];

  final moduli = <(int, String)>[
    (3329, 'mlKem'),
    (12289, 'fnDsa'),
    (8380417, 'mlDsa'),
  ];

  for (final (q, name) in moduli) {
    final barrett = BarrettParams.forQ(q);
    final mont = MontgomeryParams.forQ(q);

    // ── Barrett vs % reference ──
    results.add(_benchReduceBarrett(q, name, barrett, ctx, buildMode));
    results.add(_benchReducePercent(q, name, ctx, buildMode));

    // ── Montgomery ──
    if (mont.isReady) {
      results.add(_benchMontMul(q, name, mont, ctx, buildMode));
      results.add(_benchMontReduce(q, name, mont, ctx, buildMode));
    }
  }

  drainBenchmarkSink();
  return results;
}

// ── Barrett reduction ────────────────────────────────────────────────

BenchmarkResult _benchReduceBarrett(
  int q,
  String name,
  BarrettParams barrett,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rnd = Random(q);
  // Pre-generate products outside timing.
  final products = List<int>.generate(
    kDefaultIterations * kDefaultRounds,
    (_) => rnd.nextInt(q) * rnd.nextInt(q),
  );
  var idx = 0;
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      for (var i = 0; i < kDefaultIterations; i++) {
        final r = ModQ.reduceBarrett(products[idx++], barrett);
        blackHole += r;
      }
      observeInt(blackHole);
      idx = 0; // reset for next round
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'reduce',
    operation: 'reduceBarrett',
    profile: name,
    q: q,
    n: 0, // not a poly op
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

// ── % reference reduction ────────────────────────────────────────────

BenchmarkResult _benchReducePercent(
  int q,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rnd = Random(q);
  final products = List<int>.generate(
    kDefaultIterations * kDefaultRounds,
    (_) => rnd.nextInt(q) * rnd.nextInt(q),
  );
  var idx = 0;
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      for (var i = 0; i < kDefaultIterations; i++) {
        final r = ModQ.reduce(products[idx++], q);
        blackHole += r;
      }
      observeInt(blackHole);
      idx = 0;
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'reduce',
    operation: 'reducePercent',
    profile: name,
    q: q,
    n: 0,
    kernelMode: 'reference',
    reduceStrategy: 'percent',
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

// ── Montgomery montMul ───────────────────────────────────────────────

BenchmarkResult _benchMontMul(
  int q,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rnd = Random(q);
  // Pre-generate Montgomery-domain operands outside timing.
  final ops = List<int>.generate(
    kDefaultIterations * kDefaultRounds * 2,
    (_) => ModQ.toMont(rnd.nextInt(q), mont),
  );
  var idx = 0;
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      for (var i = 0; i < kDefaultIterations; i++) {
        final r = ModQ.montMul(ops[idx++], ops[idx++], mont);
        blackHole += r;
      }
      observeInt(blackHole);
      idx = 0;
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'reduce',
    operation: 'montMul',
    profile: name,
    q: q,
    n: 0,
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

// ── Montgomery montReduce ────────────────────────────────────────────

BenchmarkResult _benchMontReduce(
  int q,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final rnd = Random(q);
  final bound = q * mont.r;
  // nextInt is limited to 2^32; cap input generation accordingly.
  // montReduce's theoretical bound is q*R, but 2^31-1 is sufficient for
  // benchmarking purposes across all profiles.
  final cap = bound > 0x7fffffff ? 0x7fffffff : bound;
  // Pre-generate inputs within [0, cap) outside timing.
  final inputs = List<int>.generate(
    kDefaultIterations * kDefaultRounds,
    (_) => rnd.nextInt(cap),
  );
  var idx = 0;
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      for (var i = 0; i < kDefaultIterations; i++) {
        final r = ModQ.montReduce(inputs[idx++], mont);
        blackHole += r;
      }
      observeInt(blackHole);
      idx = 0;
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'reduce',
    operation: 'montReduce',
    profile: name,
    q: q,
    n: 0,
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
