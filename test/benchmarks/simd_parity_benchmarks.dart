/// SIMD NTT benchmark suite.
///
/// Measures the staged typed scalar kernel against the split-pass `Int32x4`
/// kernel for every shipped profile, forward and inverse. This measures
/// **speed only**; residue parity is enforced bit-exactly by
/// `test/simd_ntt_parity_test.dart` and is a merge gate independent of timing.
///
/// Numbers are meaningful only from `dart compile exe` (`doc/SIMD.md` §4).
/// On dart2js the vector kernel is expected to lose — the backend gate in
/// `SimdCapability` exists because of that measurement.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pqlattice/pqlattice.dart';
import 'package:pqlattice/src/ntt/ntt_scalar.dart';
import 'package:pqlattice/src/simd/ntt_simd_int32x4.dart';
import 'package:pqlattice/src/simd/ntt_workspace.dart';

import 'benchmark_harness.dart';

/// Runs the SIMD NTT benchmark matrix.
List<BenchmarkResult> runSimdParityBenchmarks({
  required BenchmarkContext ctx,
  required String buildMode,
}) {
  final results = <BenchmarkResult>[];

  for (final ring in <RingParams>[
    RingParams.mlKem,
    RingParams.mlDsa,
    RingParams.fnDsa512,
    RingParams.fnDsa1024,
  ]) {
    results.addAll(_benchProfile(ring, ctx, buildMode));
  }

  drainBenchmarkSink();
  return results;
}

List<BenchmarkResult> _benchProfile(
  RingParams ring,
  BenchmarkContext ctx,
  String buildMode,
) {
  final n = ring.n;
  final params = NttParams.forRing(ring);
  final mont = ring.q == 8380417 ? MontgomeryParams.mlDsa : null;
  final zetas = mont == null
      ? params.zetas
      : params.zetas.map((z) => ModQ.toMont(z, mont)).toList(growable: false);
  final invScale = mont == null
      ? params.invNScale
      : ModQ.toMont(params.invNScale, mont);

  final rnd = Random(0x51D ^ ring.q ^ n);
  final source = Int32List.fromList(
    List<int>.generate(n, (_) => rnd.nextInt(ring.q)),
  );
  final ws = NttWorkspace(n);

  final results = <BenchmarkResult>[];

  // ── forward ──────────────────────────────────────────────────────────────
  results.add(
    _bench(
      ctx: ctx,
      buildMode: buildMode,
      ring: ring,
      operation: 'nttForward',
      kernelMode: 'typedScalar',
      body: () {
        ws.lanes.setAll(0, source);
        switch (ring.name) {
          case 'ml-kem':
            NttScalar.mlKemForward(ws.lanes, zetas);
          case 'ml-dsa':
            NttScalar.mlDsaForward(ws.lanes, zetas);
          default:
            NttScalar.fnDsaForward(ws.lanes, n, zetas);
        }
        observeInt(ws.lanes[0]);
      },
    ),
  );
  results.add(
    _bench(
      ctx: ctx,
      buildMode: buildMode,
      ring: ring,
      operation: 'nttForward',
      kernelMode: 'simd',
      body: () {
        ws.lanes.setAll(0, source);
        switch (ring.name) {
          case 'ml-kem':
            NttSimdInt32x4.mlKemForward(ws, zetas);
          case 'ml-dsa':
            NttSimdInt32x4.mlDsaForward(ws, zetas);
          default:
            NttSimdInt32x4.fnDsaForward(ws, n, zetas);
        }
        observeInt(ws.lanes[0]);
      },
    ),
  );

  // ── inverse ──────────────────────────────────────────────────────────────
  results.add(
    _bench(
      ctx: ctx,
      buildMode: buildMode,
      ring: ring,
      operation: 'nttInverse',
      kernelMode: 'typedScalar',
      body: () {
        ws.lanes.setAll(0, source);
        switch (ring.name) {
          case 'ml-kem':
            NttScalar.mlKemInverse(ws.lanes, zetas, invScale);
          case 'ml-dsa':
            NttScalar.mlDsaInverse(ws.lanes, zetas, invScale);
          default:
            NttScalar.fnDsaInverse(ws.lanes, n, zetas, invScale);
        }
        observeInt(ws.lanes[0]);
      },
    ),
  );
  results.add(
    _bench(
      ctx: ctx,
      buildMode: buildMode,
      ring: ring,
      operation: 'nttInverse',
      kernelMode: 'simd',
      body: () {
        ws.lanes.setAll(0, source);
        switch (ring.name) {
          case 'ml-kem':
            NttSimdInt32x4.mlKemInverse(ws, zetas, invScale);
          case 'ml-dsa':
            NttSimdInt32x4.mlDsaInverse(ws, zetas, invScale);
          default:
            NttSimdInt32x4.fnDsaInverse(ws, n, zetas, invScale);
        }
        observeInt(ws.lanes[0]);
      },
    ),
  );

  return results;
}

BenchmarkResult _bench({
  required BenchmarkContext ctx,
  required String buildMode,
  required RingParams ring,
  required String operation,
  required String kernelMode,
  required void Function() body,
}) {
  final (ns, memory) = measureRounds(
    body,
    iterations: kDefaultIterations,
    rounds: kDefaultRounds,
    warmup: kDefaultWarmup,
    observe: observeInt,
  );

  return BenchmarkResult(
    suite: 'simd',
    operation: operation,
    profile: switch (ring.name) {
      'ml-kem' => 'mlKem',
      'ml-dsa' => 'mlDsa',
      'fn-dsa-512' => 'fnDsa512',
      _ => 'fnDsa1024',
    },
    q: ring.q,
    n: ring.n,
    kernelMode: kernelMode,
    reduceStrategy: ring.q == 8380417 ? 'montgomery' : 'barrett',
    layout: 'staged',
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
    memoryRssBytes: memory,
  );
}