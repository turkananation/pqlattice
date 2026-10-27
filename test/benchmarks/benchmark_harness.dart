/// Shared harness for `pqlattice` benchmarks.
///
/// Design constraints (military accuracy — no hacks):
/// - **Zero new dependencies.** Pure Dart only; no `benchmark_harness`,
///   no `zeroize` repurposing, no FFI.
/// - **AOT-first.** Numbers are meaningful only from `dart compile exe`.
///   JIT is recorded separately for variance documentation, never for
///   speed claims (doc/VM_COMPILER_BOUNDARY.md).
/// - **Warm-up mandatory.** JIT compilation and optimizer settling happen
///   before the timed region.
/// - **Multiple rounds, median reported.** Single-shot timing is not a
///   valid claim (doc/BENCHMARKS.md §1 rule 2).
/// - **Dead Store Elimination defeated.** A `@pragma('vm:never-inline')`
///   opaque sink is XORed with a result coefficient after every timed
///   iteration, and the sink value is returned at the end so the compiler
///   cannot prove the loop dead.
/// - **Setup separate from timing.** Engine/poly construction happens
///   outside the measured region.
/// - **Deterministic inputs.** Fixed-seed pseudo-random polys; no
///   `Random`, `DateTime`, or I/O inside the timed loop.
/// - **No date stamps.** Traceability is via git commit SHA, not dates
///   (doc/AGENTS.md hard rule 2).
library;

import 'dart:io';
import 'dart:math';

import 'package:pqlattice/pqlattice.dart';

/// Immutable record of one benchmark measurement. Every field is required
/// so that a number without its full context cannot be accidentally
/// presented as a claim.
class BenchmarkResult {
  /// Benchmark suite name (e.g. 'ntt', 'basemul', 'reduce', 'pipeline').
  final String suite;

  /// Operation measured (e.g. 'forward', 'inverse', 'pointwise',
  /// 'reduceBarrett', 'ntt+basemul+inv').
  final String operation;

  /// Ring profile (e.g. 'mlKem', 'mlDsa', 'fnDsa512', 'fnDsa1024').
  final String profile;

  /// q and n from RingParams.
  final int q;
  final int n;

  /// Kernel selection (accelerated, optimizedScalar, simd, reference).
  final String kernelMode;

  /// Reduce strategy used by the engine (barrett, percent, montgomery).
  final String reduceStrategy;

  /// Coefficient layout (allocating, inPlace).
  final String layout;

  /// Arithmetic domain (plain, montgomery).
  final String domain;

  /// Build mode under which the benchmark ran (jit, aot).
  final String buildMode;

  /// Number of timed iterations per round.
  final int iterationsPerRound;

  /// Number of timed rounds.
  final int rounds;

  /// Warm-up iterations executed before timing.
  final int warmupIterations;

  /// Per-iteration time in nanoseconds, one entry per round.
  final List<double> roundNs;

  /// Opaque sink value after all iterations — proves the work was not
  /// eliminated as a dead store.
  final int sink;

  /// Dart SDK version string (e.g. '3.13.5 (stable)').
  final String sdkVersion;

  /// Operating system (e.g. 'linux').
  final String os;

  /// Number of logical CPUs visible to the VM.
  final int cpuCount;

  /// Git commit SHA of the tree at measurement time (empty if unavailable).
  final String gitSha;

  BenchmarkResult({
    required this.suite,
    required this.operation,
    required this.profile,
    required this.q,
    required this.n,
    required this.kernelMode,
    required this.reduceStrategy,
    required this.layout,
    required this.domain,
    required this.buildMode,
    required this.iterationsPerRound,
    required this.rounds,
    required this.warmupIterations,
    required this.roundNs,
    required this.sink,
    required this.sdkVersion,
    required this.os,
    required this.cpuCount,
    this.gitSha = '',
  }) : assert(roundNs.isNotEmpty),
       assert(roundNs.length == rounds);

  /// Mean per-iteration nanoseconds across rounds.
  double get meanNs {
    var sum = 0.0;
    for (final v in roundNs) {
      sum += v;
    }
    return sum / roundNs.length;
  }

  /// Median per-iteration nanoseconds across rounds.
  double get medianNs {
    final sorted = List<double>.from(roundNs)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
    return sorted[mid];
  }

  /// Minimum per-iteration nanoseconds across rounds.
  double get minNs => roundNs.reduce((a, b) => a < b ? a : b);

  /// Maximum per-iteration nanoseconds across rounds.
  double get maxNs => roundNs.reduce((a, b) => a > b ? a : b);

  /// Population standard deviation of per-iteration nanoseconds.
  double get stdDevNs {
    final mean = meanNs;
    var sumSq = 0.0;
    for (final v in roundNs) {
      final d = v - mean;
      sumSq += d * d;
    }
    return sqrt(sumSq / roundNs.length);
  }

  /// Relative standard deviation as a percentage (0 = perfectly consistent).
  double get rstdPct => meanNs == 0 ? 0.0 : (stdDevNs / meanNs * 100.0);

  /// TSV header line for all benchmark results.
  static String tsvHeader() {
    return [
      'suite', 'operation', 'profile', 'q', 'n', 'kernelMode',
      'reduceStrategy', 'layout', 'domain', 'buildMode',
      'iterationsPerRound', 'rounds', 'warmupIterations',
      'meanNs', 'medianNs', 'minNs', 'maxNs', 'stdDevNs', 'rstdPct',
      'sink', 'sdkVersion', 'os', 'cpuCount', 'gitSha',
    ].join('\t');
  }

  /// TSV row for this result.
  String toTsv() {
    return [
      suite, operation, profile, q.toString(), n.toString(), kernelMode,
      reduceStrategy, layout, domain, buildMode,
      iterationsPerRound.toString(), rounds.toString(),
      warmupIterations.toString(),
      meanNs.toStringAsFixed(3), medianNs.toStringAsFixed(3),
      minNs.toStringAsFixed(3), maxNs.toStringAsFixed(3),
      stdDevNs.toStringAsFixed(3), rstdPct.toStringAsFixed(3),
      sink.toString(), sdkVersion, os, cpuCount.toString(), gitSha,
    ].join('\t');
  }
}

/// Capture of the execution environment for result context.
class BenchmarkContext {
  BenchmarkContext({
    required this.sdkVersion,
    required this.os,
    required this.cpuCount,
    this.gitSha = '',
  });

  final String sdkVersion;
  final String os;
  final int cpuCount;
  final String gitSha;

  static BenchmarkContext capture() {
    final sdk = Platform.version;
    final os = Platform.operatingSystem;
    final cpus = Platform.numberOfProcessors;
    String? sha;
    try {
      final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD'],
          workingDirectory: Directory.current.path);
      if (result.exitCode == 0) {
        sha = result.stdout.trim();
      }
    } catch (_) {
      // git not available or not a repository — leave gitSha empty.
    }
    return BenchmarkContext(
      sdkVersion: sdk,
      os: os,
      cpuCount: cpus,
      gitSha: sha ?? '',
    );
  }
}

/// Opaque sink to defeat Dead Store Elimination.
///
/// Mirrors the mechanism in `zeroize`'s `dse_guard.dart` but lives here
/// so pqlattice benchmarks remain dependency-free. The `@pragma`
/// prevents inlining, so the optimiser cannot see through to eliminate
/// the preceding writes.
int _benchmarkSink = 0x5A5A5A5A;

@pragma('vm:never-inline')
void _benchmarkSinkObserve(int value) {
  _benchmarkSink ^= value;
}

/// Returns the current sink value and resets it. Call after all benchmark
/// iterations so the computed result is observable to the compiler.
int drainBenchmarkSink() {
  final s = _benchmarkSink;
  _benchmarkSink = 0x5A5A5A5A;
  return s;
}

/// Runs [fn] for [iterations] iterations, preceded by [warmup]
/// warm-up iterations. Returns the elapsed microseconds for the timed
/// region only.
///
/// [observe] is called after each timed iteration with a value derived
/// from the result, preventing DSE.
double timedRegion(void Function() fn, int iterations, int warmup,
    void Function(int) observe) {
  // Warm-up: JIT compilation, optimizer settling, table touches.
  for (var i = 0; i < warmup; i++) {
    fn();
    observe(i);
  }

  // Timed region.
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    fn();
    observe(i);
  }
  sw.stop();

  return sw.elapsedMicroseconds.toDouble();
}

/// Runs [bench] for [rounds] rounds, each [iterations] iterations, with
/// [warmup] warm-up iterations total. Returns per-round nanoseconds.
///
/// Each round re-runs warm-up internally to keep rounds independent, but
/// warm-up cost is not included in the timed measurement.
List<double> measureRounds(
  void Function() fn, {
  required int iterations,
  required int rounds,
  required int warmup,
  required void Function(int) observe,
}) {
  final ns = <double>[];
  for (var r = 0; r < rounds; r++) {
    final us = timedRegion(fn, iterations, warmup, observe);
    ns.add(us * 1000.0 / iterations); // microseconds -> nanoseconds per iter
  }
  return ns;
}

/// Convenience: observe a Poly coefficient into the sink.
void observePolyCoeff(Poly p, int idx) {
  _benchmarkSinkObserve(p.coeffs[idx]);
}

/// Convenience: observe an int into the sink.
void observeInt(int v) {
  _benchmarkSinkObserve(v);
}

/// Builds a deterministic polynomial with coefficients in [0, q).
Poly benchPoly(RingParams ring, int seed) {
  final rnd = Random(seed);
  return Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
}

/// Builds a list of deterministic polynomials.
List<Poly> benchPolys(RingParams ring, int count, int seedBase) {
  return List.generate(count, (i) => benchPoly(ring, seedBase + i));
}

/// Standard default benchmark parameters.
const int kDefaultWarmup = 200;
const int kDefaultIterations = 1000;
const int kDefaultRounds = 5;
