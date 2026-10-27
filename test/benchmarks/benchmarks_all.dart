/// Entry point for the `pqlattice` benchmark suite.
///
/// Usage:
///   # JIT (dev only — not for public speed claims)
///   dart run test/benchmarks/benchmarks_all.dart
///
///   # AOT (required for claim-quality numbers)
///   dart compile exe test/benchmarks/benchmarks_all.dart -o /tmp/pq_bench
///   /tmp/pq_bench
///
/// Output is TSV on stdout, one row per measurement, with a header line.
/// Every row carries full context (profile, q, n, kernelMode, reduce
/// strategy, layout, domain, buildMode, SDK, OS, CPU count, git SHA) so
/// that a number cannot be presented without its context.
///
/// Exit code is 0 when all suites complete; non-zero on failure.
library;

import 'dart:io';

import 'basemul_benchmarks.dart';
import 'benchmark_harness.dart';
import 'ntt_benchmarks.dart';
import 'pipeline_benchmarks.dart';
import 'reduce_benchmarks.dart';
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
  final buildMode = _detectBuildMode();
  final ctx = BenchmarkContext.capture();

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
    final simd = runSimdParityBenchmarks(ctx: ctx, buildMode: buildMode);
    for (final r in simd) {
      print(r.toTsv());
    }
  } catch (e, st) {
    errorOccurred = true;
    stderr.writeln('simd benchmarks failed: $e\n$st');
  }

  exit(errorOccurred ? 1 : 0);
}
