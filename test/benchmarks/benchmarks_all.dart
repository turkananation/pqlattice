/// Entry point for the `pqlattice` benchmark suite.
///
/// Usage:
///   # JIT (dev only — not for public speed claims)
///   dart run test/benchmarks/benchmarks_all.dart --mode jit
///
///   # AOT (required for claim-quality numbers)
///   dart compile exe test/benchmarks/benchmarks_all.dart -o /tmp/pq_bench
///   /tmp/pq_bench --mode aot
///
///   # JIT vs AOT variance (run both, compare)
///   dart run test/benchmarks/benchmarks_all.dart --mode jit > jit.tsv
///   /tmp/pq_bench --mode aot > aot.tsv
///
///   # Memory measurement
///   dart run test/benchmarks/benchmarks_all.dart --measure-memory > mem.tsv
///
/// Output is TSV on stdout, one row per measurement, with a header line.
/// Every row carries full context (profile, q, n, kernelMode, reduce
/// strategy, layout, domain, buildMode, SDK, OS, CPU count, git SHA,
/// memoryRssBytes) so that a number cannot be presented without its context.
///
/// Exit code is 0 when all suites complete; non-zero on failure.
library;

import 'dart:io';

import 'basemul_benchmarks.dart';
import 'benchmark_harness.dart';
import 'ntt_benchmarks.dart';
import 'pipeline_benchmarks.dart';
import 'polyvec_benchmarks.dart';
import 'reduce_benchmarks.dart';
import 'schoolbook_benchmarks.dart';
import 'simd_parity_benchmarks.dart';

/// Determines build mode from how this executable was launched.
///
/// A compiled `.exe` is AOT; `dart run` on a `.dart` script is JIT.
/// This is a heuristic; the authoritative build mode should be recorded
/// by CI based on how it invokes the binary.
String _detectBuildMode() {
  final script = Platform.script.toString();
  if (script.endsWith('.exe') ||
      script.contains('snapshot') ||
      !script.endsWith('.dart')) {
    return 'aot';
  }
  return 'jit';
}

void main(List<String> args) {
  var buildMode = _detectBuildMode();
  var measureMemory = false;

  // Parse CLI args: --mode jit|aot, --measure-memory
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--mode':
        if (i + 1 < args.length) {
          buildMode = args[++i];
          overrideBuildMode(buildMode);
        }
      case '--measure-memory':
        measureMemory = true;
        enableMemoryMeasurement();
      case '--help':
        print('Usage: benchmarks_all.dart [--mode jit|aot] [--measure-memory]');
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }

  final ctx = BenchmarkContext.capture();

  // Capture RSS before all suites if memory measurement is enabled.
  final beforeRss = measureMemory ? captureRssBytes() : null;

  // Print header first so downstream consumers can parse even if a
  // later suite fails.
  print(BenchmarkResult.tsvHeader());

  var errorOccurred = false;

  try {
    final ntt = runNttBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in ntt) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('ntt benchmarks failed: $e\n$st');
  }

  try {
    final basemul = runBasemulBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in basemul) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('basemul benchmarks failed: $e\n$st');
  }

  try {
    final reduce = runReduceBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in reduce) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('reduce benchmarks failed: $e\n$st');
  }

  try {
    final pipeline = runPipelineBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in pipeline) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('pipeline benchmarks failed: $e\n$st');
  }

  try {
    final polyvec = runPolyVecBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in polyvec) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('polyvec benchmarks failed: $e\n$st');
  }

  try {
    final schoolbook = runSchoolbookBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in schoolbook) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('schoolbook benchmarks failed: $e\n$st');
  }

  try {
    final simd = runSimdParityBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in simd) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('simd benchmarks failed: $e\n$st');
  }

  // Capture RSS after all suites and print a memory summary row.
  if (measureMemory) {
    final afterRss = captureRssBytes();
    if (beforeRss != null && afterRss != null) {
      final delta = afterRss - beforeRss;
      stderr.writeln(
        'MEMORY_SUMMARY beforeRssBytes=$beforeRss afterRssBytes=$afterRss '
        'deltaBytes=$delta',
      );
    }
  }

  exit(errorOccurred ? 1 : 0);
}
