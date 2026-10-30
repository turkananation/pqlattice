/// Basemul benchmark suite.
///
/// Measures NTT-domain pointwise multiplication (ML-DSA / FN-DSA style)
/// and ML-KEM pair basemul (incomplete NTT style), in both allocating and
/// in-place layouts, for every shipped profile.
///
/// Montgomery-domain variants are measured where the engine supports them.
/// All inputs are deterministic fixed-seed polys; timing excludes setup.
library;

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Runs all basemul benchmarks and appends results to [out].
List<BenchmarkResult> runBasemulBenchmarks({
  required BenchmarkContext ctx,
  required String buildMode,
}) {
  final results = <BenchmarkResult>[];

  // ── Complete-style pointwise (ML-DSA, FN-DSA-512, FN-DSA-1024) ──
  final pointwiseProfiles = <(RingParams, String)>[
    (RingParams.mlDsa, 'mlDsa'),
    (RingParams.fnDsa512, 'fnDsa512'),
    (RingParams.fnDsa1024, 'fnDsa1024'),
  ];
  for (final (ring, name) in pointwiseProfiles) {
    final mont = MontgomeryParams.forQ(ring.q);
    results.add(_benchPointwiseAlloc(ring, name, ctx, buildMode));
    results.add(_benchPointwiseInPlace(ring, name, ctx, buildMode));
    if (mont.isReady) {
      results.add(
        _benchPointwiseMontgomeryAlloc(ring, name, mont, ctx, buildMode),
      );
      results.add(
        _benchPointwiseMontgomeryInPlace(ring, name, mont, ctx, buildMode),
      );
    }
  }

  // ── ML-KEM pair basemul (incomplete NTT) ──
  final kem = RingParams.mlKem;
  final kemMont = MontgomeryParams.forQ(kem.q);
  results.add(_benchMlKemPairsAlloc(kem, ctx, buildMode));
  results.add(_benchMlKemPairsInPlace(kem, ctx, buildMode));
  if (kemMont.isReady) {
    results.add(_benchMlKemPairsMontgomeryAlloc(kem, kemMont, ctx, buildMode));
    results.add(
      _benchMlKemPairsMontgomeryInPlace(kem, kemMont, ctx, buildMode),
    );
  }

  drainBenchmarkSink();
  return results;
}

// ── Pointwise (complete-style NTT) ──────────────────────────────────

BenchmarkResult _benchPointwiseAlloc(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  final a = benchPoly(ring, 0x1753);
  final b = benchPoly(ring, 0xBEEF);
  var blackHole = 0;

  final (ns, _) = measureRounds(
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
    suite: 'basemul',
    operation: 'pointwise',
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

BenchmarkResult _benchPointwiseInPlace(
  RingParams ring,
  String name,
  BenchmarkContext ctx,
  String buildMode,
) {
  // Setup (doc/BENCHMARKS.md §4): inputs and destination are built once,
  // outside the timed region. pointwiseInPlace fully overwrites dest on
  // every call, so the timed closure measures only the in-place op.
  final a = benchPoly(ring, 0xCAFE);
  final b = benchPoly(ring, 0xDEAD);
  final c = Poly.zero(ring);
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      Basemul.pointwiseInPlace(c, a, b, ring);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'pointwise',
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

// ── Pointwise Montgomery ────────────────────────────────────────────

BenchmarkResult _benchPointwiseMontgomeryAlloc(
  RingParams ring,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final a = benchPoly(ring, 0x1753);
  final b = benchPoly(ring, 0xBEEF);
  // Convert inputs to Montgomery domain once (setup).
  final aMont = Poly.zero(ring);
  final bMont = Poly.zero(ring);
  for (var i = 0; i < ring.n; i++) {
    aMont.coeffs[i] = ModQ.toMont(a.coeffs[i], mont);
    bMont.coeffs[i] = ModQ.toMont(b.coeffs[i], mont);
  }
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      final c = Basemul.pointwiseMontgomery(aMont, bMont, ring, mont);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'pointwise',
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

BenchmarkResult _benchPointwiseMontgomeryInPlace(
  RingParams ring,
  String name,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  // Setup (doc/BENCHMARKS.md §4): real-domain inputs, their Montgomery
  // conversion, and the destination are all pre-built outside the timed
  // region; the closure measures only the in-place Montgomery op.
  final a = benchPoly(ring, 0xCAFE);
  final b = benchPoly(ring, 0xDEAD);
  final aMont = Poly.zero(ring);
  final bMont = Poly.zero(ring);
  final c = Poly.zero(ring);
  for (var i = 0; i < ring.n; i++) {
    aMont.coeffs[i] = ModQ.toMont(a.coeffs[i], mont);
    bMont.coeffs[i] = ModQ.toMont(b.coeffs[i], mont);
  }
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      Basemul.pointwiseMontgomeryInPlace(c, aMont, bMont, ring, mont);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'pointwise',
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

// ── ML-KEM pair basemul (incomplete NTT) ────────────────────────────

BenchmarkResult _benchMlKemPairsAlloc(
  RingParams ring,
  BenchmarkContext ctx,
  String buildMode,
) {
  final a = benchPoly(ring, 0x1753);
  final b = benchPoly(ring, 0xBEEF);
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      final c = Basemul.mlKemPairs(a, b, ring);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'mlKemPairs',
    profile: 'mlKem',
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

BenchmarkResult _benchMlKemPairsInPlace(
  RingParams ring,
  BenchmarkContext ctx,
  String buildMode,
) {
  // Setup (doc/BENCHMARKS.md §4): inputs and destination built once,
  // outside the timed region; mlKemPairsInPlace fully overwrites dest.
  final a = benchPoly(ring, 0xCAFE);
  final b = benchPoly(ring, 0xDEAD);
  final c = Poly.zero(ring);
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      Basemul.mlKemPairsInPlace(c, a, b);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'mlKemPairs',
    profile: 'mlKem',
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

// ── ML-KEM pair basemul Montgomery ──────────────────────────────────

BenchmarkResult _benchMlKemPairsMontgomeryAlloc(
  RingParams ring,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  final a = benchPoly(ring, 0x1753);
  final b = benchPoly(ring, 0xBEEF);
  // Convert to Montgomery domain once (setup).
  final aMont = Poly.zero(ring);
  final bMont = Poly.zero(ring);
  for (var i = 0; i < ring.n; i++) {
    aMont.coeffs[i] = ModQ.toMont(a.coeffs[i], mont);
    bMont.coeffs[i] = ModQ.toMont(b.coeffs[i], mont);
  }
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      final c = Basemul.mlKemPairsMontgomery(aMont, bMont, mont);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'mlKemPairs',
    profile: 'mlKem',
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

BenchmarkResult _benchMlKemPairsMontgomeryInPlace(
  RingParams ring,
  MontgomeryParams mont,
  BenchmarkContext ctx,
  String buildMode,
) {
  // Setup (doc/BENCHMARKS.md §4): real-domain inputs, their Montgomery
  // conversion, and the destination pre-built outside the timed region.
  final a = benchPoly(ring, 0xCAFE);
  final b = benchPoly(ring, 0xDEAD);
  final aMont = Poly.zero(ring);
  final bMont = Poly.zero(ring);
  final c = Poly.zero(ring);
  for (var i = 0; i < ring.n; i++) {
    aMont.coeffs[i] = ModQ.toMont(a.coeffs[i], mont);
    bMont.coeffs[i] = ModQ.toMont(b.coeffs[i], mont);
  }
  var blackHole = 0;

  final (ns, _) = measureRounds(
    () {
      Basemul.mlKemPairsMontgomeryInPlace(c, aMont, bMont, mont);
      blackHole += c.coeffs[0];
      observeInt(blackHole);
    },
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: (i) => observeInt(i),
  );

  return BenchmarkResult(
    suite: 'basemul',
    operation: 'mlKemPairs',
    profile: 'mlKem',
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
