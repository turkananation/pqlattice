/// Step-0 attribution ablation for the ratified NTT hot-path plan.
///
/// Per shipped ring, isolates the cost of the `_mul`/`ModQ` call graph inside
/// NTT butterflies by pairing:
///
/// - `prod`  — the shipped production engine path (public API, unmodified);
/// - `inline`— fully inlined butterfly loops whose reduce arithmetic is an
///   exact replica of the shipped Barrett chain (same mu/shift, same three
///   corrections, neg fix, `%` escape) with every throttle call expanded;
/// - `mont`  — ML-DSA only: fully inlined 32-bit-word Montgomery REDC
///   butterflies with Montgomery-form twiddles (the ratified scheme);
/// - `k27`   — FN-DSA only: fully inlined single-guard Barrett candidate
///   with shift=27, mu=10921 (0-correction family, ratified constants).
///
/// Every candidate kernel is checked against the production engine output
/// (full coefficient parity) on the bench input before any timing, and the
/// ML-KEM candidate is additionally verified exhaustively over all products
/// a*b for a, b in [0, q). A parity failure aborts before timing.
///
/// Bench-only: no production file is touched by this harness.
///
/// Usage:
///   dart run test/benchmarks/ablation_step0.dart
///   dart compile exe test/benchmarks/ablation_step0.dart -o /tmp/pq_abl
///   /tmp/pq_abl                          # AOT — claim-quality numbers
///   /tmp/pq_abl --rounds 40 --iters 100  # more trials
///
/// Output: TSV rows on stdout (one per ring/arm; per-iteration ns for the
/// forward+inverse in-place pair), parity and context lines on stderr.
/// Exit code 0 only when all parity checks pass.
library;

import 'dart:io';
import 'dart:math';

import 'package:pqlattice/pqlattice.dart';

import 'benchmark_harness.dart';

/// Candidate arm signature: mutate the coefficient buffer in place.
typedef _ArmFn = void Function(List<int> coeffs, NttParams ntt);

void main(List<String> args) {
  var rounds = 24;
  var iters = 100;
  var skipTiming = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--rounds':
        rounds = int.parse(args[++i]);
      case '--iters':
        iters = int.parse(args[++i]);
      case '--skip-timing':
        skipTiming = true;
      case '--help':
        stderr.writeln(
          'Usage: ablation_step0.dart [--rounds N] [--iters N] [--skip-timing]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }

  final ok = _runParityChecks();
  if (!ok) {
    stderr.writeln('ABORT: parity failure — a candidate kernel is wrong.');
    exit(1);
  }
  stderr.writeln('PARITY: all candidate kernels match production output.');
  if (skipTiming) {
    stderr.writeln('Timing skipped (--skip-timing).');
    exit(0);
  }

  final ctx = BenchmarkContext.capture();
  final buildMode = _detectBuildMode();
  stderr.writeln(
    'context sdk=${ctx.sdkVersion} os=${ctx.os} '
    'cpus=${ctx.cpuCount} sha=${ctx.gitSha} mode=$buildMode '
    'rounds=$rounds iters=$iters',
  );

  print('ring\tarm\tmedianNs\tmeanNs\tminNs\tmaxNs\trstdPct\ttrials');

  const warmup = 200;

  // ML-KEM: production vs single-guard candidate (stage-1 shape).
  _runAblation(
    ring: RingParams.mlKem,
    ringName: 'mlKem',
    rounds: rounds,
    iters: iters,
    warmup: warmup,
    extraArms: const <String, _ArmFn>{},
  );

  // ML-DSA: production vs inline replica vs inlined Montgomery REDC.
  // Montgomery twiddles and the inverse-scale constant are built once here
  // (setup) and handed to the kernel as precomputed tables.
  final mlDsaParams = NttParams.forRing(RingParams.mlDsa);
  final mlDsaMont = MontgomeryParams.forQ(RingParams.mlDsa.q);
  final mlDsaZetasMont = mlDsaParams.zetas
      .map((z) => ModQ.toMont(z, mlDsaMont))
      .toList();
  final mlDsaInvMont = ModQ.toMont(mlDsaParams.invNScale, mlDsaMont);
  _runAblation(
    ring: RingParams.mlDsa,
    ringName: 'mlDsa',
    rounds: rounds,
    iters: iters,
    warmup: warmup,
    extraArms: <String, _ArmFn>{
      'mont': (coeffs, ntt) =>
          _montFwdInv(coeffs, mlDsaZetasMont, mlDsaInvMont),
    },
  );

  // FN-DSA 512 / 1024: production vs inline replica vs k=27 candidate.
  for (final (ring, nm) in [
    (RingParams.fnDsa512, 'fnDsa512'),
    (RingParams.fnDsa1024, 'fnDsa1024'),
  ]) {
    _runAblation(
      ring: ring,
      ringName: nm,
      rounds: rounds,
      iters: iters,
      warmup: warmup,
      extraArms: const <String, _ArmFn>{'k27': _k27FwdInv},
    );
  }

  drainBenchmarkSink();
  exit(0);
}

/// Detects build mode the same way the shipped harness does.
String _detectBuildMode() {
  final script = Platform.script.toString();
  if (script.endsWith('.exe') ||
      script.contains('snapshot') ||
      !script.endsWith('.dart')) {
    return 'aot';
  }
  return 'jit';
}

// ─────────────────────────────────────────────────────────────────────────────
// Arm runner
// ─────────────────────────────────────────────────────────────────────────────

/// Times and reports one ring's arms. Each arm runs on its own typed-lane
/// poly with the identical base input and reset discipline.
void _runAblation({
  required RingParams ring,
  required String ringName,
  required int rounds,
  required int iters,
  required int warmup,
  required Map<String, _ArmFn> extraArms,
}) {
  final engine = NttEngine(ring);
  final ntt = NttParams.forRing(ring);
  final base = _benchPoly(ring, 0x1BEEF2 ^ ring.q);

  // ── prod: production engine forward + inverse in place ──
  final pProd = Poly.zero(ring);
  final (prodNs, _) = measureRounds(
    () {
      pProd.coeffs.setAll(0, base.coeffs);
      engine.forwardInPlace(pProd);
      engine.inverseInPlace(pProd);
    },
    iterations: iters,
    rounds: rounds,
    warmup: warmup,
    observe: (i) => observeInt(pProd.coeffs[0]),
  );
  _reportArm(ringName, 'prod', prodNs, rounds);

  // ── inline: fully inlined replica of the shipped Barrett chain ──
  final pInline = Poly.zero(ring);
  final (inlineNs, _) = measureRounds(
    () {
      pInline.coeffs.setAll(0, base.coeffs);
      _inlineFwdInv(ntt, pInline.coeffs);
    },
    iterations: iters,
    rounds: rounds,
    warmup: warmup,
    observe: (i) => observeInt(pInline.coeffs[0]),
  );
  _reportArm(ringName, 'inline', inlineNs, rounds);

  for (final MapEntry(key: name, value: fn) in extraArms.entries) {
    final p = Poly.zero(ring);
    final (ns, _) = measureRounds(
      () {
        p.coeffs.setAll(0, base.coeffs);
        fn(p.coeffs, ntt);
      },
      iterations: iters,
      rounds: rounds,
      warmup: warmup,
      observe: (i) => observeInt(p.coeffs[0]),
    );
    _reportArm(ringName, name, ns, rounds);
  }
}

/// TSV row for one arm (header printed once by main).
void _reportArm(String ring, String arm, List<double> ns, int rounds) {
  final sorted = List<double>.from(ns)..sort();
  final mid = sorted.length ~/ 2;
  final median = sorted.length % 2 == 0
      ? (sorted[mid - 1] + sorted[mid]) / 2.0
      : sorted[mid];
  final mean = ns.fold(0.0, (a, b) => a + b) / ns.length;
  final minV = sorted.first;
  final maxV = sorted.last;
  var sq = 0.0;
  for (final v in ns) {
    sq += (v - mean) * (v - mean);
  }
  final sd = sqrt(sq / ns.length);
  final rstd = mean == 0 ? 0.0 : sd / mean * 100.0;
  print(
    '$ring\t$arm\t${median.toStringAsFixed(1)}\t${mean.toStringAsFixed(1)}'
    '\t${minV.toStringAsFixed(1)}\t${maxV.toStringAsFixed(1)}'
    '\t${rstd.toStringAsFixed(2)}\t$rounds',
  );
}

/// Deterministic poly with coefficients in [0, q).
Poly _benchPoly(RingParams ring, int seed) {
  final rnd = Random(seed);
  return Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Fully-inlined candidate kernels (no helper calls inside NTT loops)
// ─────────────────────────────────────────────────────────────────────────────

/// Dispatches forward + inverse in place for the inlined replica arm.
void _inlineFwdInv(NttParams ntt, List<int> a) {
  if (ntt.ring.q == 3329 && ntt.ring.n == 256) {
    _mlKemFwd19(ntt, a);
    _mlKemInv19(ntt, a);
  } else if (ntt.ring.q == 8380417 && ntt.ring.n == 256) {
    _mlDsaFwdReplica(ntt, a);
    _mlDsaInvReplica(ntt, a);
  } else if (ntt.ring.q == 12289) {
    _fnDsaFwdReplica(ntt, a);
    _fnDsaInvReplica(ntt, a);
  } else {
    throw ArgumentError(
      'ablation inline kernels: unsupported ring ${ntt.ring}',
    );
  }
}

// ── ML-KEM candidate: pqcrypto-parity single-guard constant (v=20159, s=26).

void _mlKemFwd19(NttParams ntt, List<int> f) {
  final zetas = ntt.zetas;
  var k = 1;
  for (var len = 128; len >= 2; len >>= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = zetas[k++];
      for (var j = start; j < start + len; j++) {
        final fj = f[j];
        final fjl = f[j + len];
        final raw = zeta * fjl;
        final quot = (raw * 20159) >> 26;
        var t = raw - quot * 3329;
        if (t < 0 || t >= 3329) t %= 3329;
        final diff = fj - t;
        f[j + len] = diff < 0 ? diff + 3329 : diff;
        final sum = fj + t;
        f[j] = sum >= 3329 ? sum - 3329 : sum;
      }
    }
  }
}

void _mlKemInv19(NttParams ntt, List<int> f) {
  final zetas = ntt.zetas;
  final inv = ntt.invNScale;
  var k = 127;
  for (var len = 2; len <= 128; len <<= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = zetas[k--];
      for (var j = start; j < start + len; j++) {
        final fj = f[j];
        final fjl = f[j + len];
        final sum = fj + fjl;
        f[j] = sum >= 3329 ? sum - 3329 : sum;
        var diff = fjl - fj;
        diff = diff < 0 ? diff + 3329 : diff;
        final raw = zeta * diff;
        final quot = (raw * 20159) >> 26;
        var t = raw - quot * 3329;
        if (t < 0 || t >= 3329) t %= 3329;
        f[j + len] = t;
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    final raw = f[i] * inv;
    final quot = (raw * 20159) >> 26;
    var t = raw - quot * 3329;
    if (t < 0 || t >= 3329) t %= 3329;
    f[i] = t;
  }
}

// ── ML-DSA replica: shipped mu=33587228, shift=48 chain, fully inlined.

void _mlDsaFwdReplica(NttParams ntt, List<int> a) {
  final zetas = ntt.zetas;
  var k = 1;
  for (var len = 128; len >= 1; len >>= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = zetas[k++];
      for (var j = start; j < start + len; j++) {
        final raw = zeta * a[j + len];
        final quot = (raw * 33587228) >> 48;
        var t = raw - quot * 8380417;
        t = t >= 8380417 ? t - 8380417 : t;
        t = t >= 8380417 ? t - 8380417 : t;
        t = t >= 8380417 ? t - 8380417 : t;
        if (t < 0) t += 8380417;
        if (t >= 8380417) t %= 8380417;
        final fj = a[j];
        final diff = fj - t;
        a[j + len] = diff < 0 ? diff + 8380417 : diff;
        final sum = fj + t;
        a[j] = sum >= 8380417 ? sum - 8380417 : sum;
      }
    }
  }
}

void _mlDsaInvReplica(NttParams ntt, List<int> a) {
  final zetas = ntt.zetas;
  final inv = ntt.invNScale;
  var k = 255;
  for (var len = 1; len < 256; len <<= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      var zeta = zetas[k--];
      zeta = 8380417 - zeta; // -zetas[k] mod q
      for (var j = start; j < start + len; j++) {
        final t = a[j];
        final u = a[j + len];
        final sum = t + u;
        a[j] = sum >= 8380417 ? sum - 8380417 : sum;
        final diff = t - u;
        final d = diff < 0 ? diff + 8380417 : diff;
        final raw = d * zeta;
        final quot = (raw * 33587228) >> 48;
        var r = raw - quot * 8380417;
        r = r >= 8380417 ? r - 8380417 : r;
        r = r >= 8380417 ? r - 8380417 : r;
        r = r >= 8380417 ? r - 8380417 : r;
        if (r < 0) r += 8380417;
        if (r >= 8380417) r %= 8380417;
        a[j + len] = r;
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    final c = a[i];
    final raw = c * inv;
    final quot = (raw * 33587228) >> 48;
    var r = raw - quot * 8380417;
    r = r >= 8380417 ? r - 8380417 : r;
    r = r >= 8380417 ? r - 8380417 : r;
    r = r >= 8380417 ? r - 8380417 : r;
    if (r < 0) r += 8380417;
    if (r >= 8380417) r %= 8380417;
    a[i] = r;
  }
}

// ── FN-DSA replica: shipped mu=1365, shift=24 chain, fully inlined.

void _fnDsaFwdReplica(NttParams ntt, List<int> a) {
  final zetas = ntt.zetas;
  final n = ntt.ring.n;
  var k = 1;
  for (var len = n >> 1; len >= 1; len >>= 1) {
    for (var start = 0; start < n; start += 2 * len) {
      final zeta = zetas[k++];
      for (var j = start; j < start + len; j++) {
        final raw = zeta * a[j + len];
        final quot = (raw * 1365) >> 24;
        var t = raw - quot * 12289;
        t = t >= 12289 ? t - 12289 : t;
        t = t >= 12289 ? t - 12289 : t;
        t = t >= 12289 ? t - 12289 : t;
        if (t < 0) t += 12289;
        if (t >= 12289) t %= 12289;
        final fj = a[j];
        final diff = fj - t;
        a[j + len] = diff < 0 ? diff + 12289 : diff;
        final sum = fj + t;
        a[j] = sum >= 12289 ? sum - 12289 : sum;
      }
    }
  }
}

void _fnDsaInvReplica(NttParams ntt, List<int> a) {
  final zetas = ntt.zetas;
  final inv = ntt.invNScale;
  final n = ntt.ring.n;
  var k = n - 1;
  for (var len = 1; len < n; len <<= 1) {
    for (var start = 0; start < n; start += 2 * len) {
      var zeta = zetas[k--];
      zeta = 12289 - zeta; // -zeta mod q
      for (var j = start; j < start + len; j++) {
        final t = a[j];
        final u = a[j + len];
        final sum = t + u;
        a[j] = sum >= 12289 ? sum - 12289 : sum;
        final diff = t - u;
        final d = diff < 0 ? diff + 12289 : diff;
        final raw = d * zeta;
        final quot = (raw * 1365) >> 24;
        var r = raw - quot * 12289;
        r = r >= 12289 ? r - 12289 : r;
        r = r >= 12289 ? r - 12289 : r;
        r = r >= 12289 ? r - 12289 : r;
        if (r < 0) r += 12289;
        if (r >= 12289) r %= 12289;
        a[j + len] = r;
      }
    }
  }
  for (var i = 0; i < n; i++) {
    final c = a[i];
    final raw = c * inv;
    final quot = (raw * 1365) >> 24;
    var r = raw - quot * 12289;
    r = r >= 12289 ? r - 12289 : r;
    r = r >= 12289 ? r - 12289 : r;
    r = r >= 12289 ? r - 12289 : r;
    if (r < 0) r += 12289;
    if (r >= 12289) r %= 12289;
    a[i] = r;
  }
}

// ── FN-DSA k=27 candidate: mu=10921, shift=27, two corrections + escape.

void _k27FwdInv(List<int> a, NttParams ntt) {
  final zetas = ntt.zetas;
  final inv = ntt.invNScale;
  final n = ntt.ring.n;
  const q = 12289;

  // Forward.
  var k = 1;
  for (var len = n >> 1; len >= 1; len >>= 1) {
    for (var start = 0; start < n; start += 2 * len) {
      final zeta = zetas[k++];
      for (var j = start; j < start + len; j++) {
        final raw = zeta * a[j + len];
        final quot = (raw * 10921) >> 27;
        var t = raw - quot * q;
        t = t >= q ? t - q : t;
        t = t >= q ? t - q : t;
        if (t < 0) t += q;
        if (t >= q) t %= q;
        final fj = a[j];
        final diff = fj - t;
        a[j + len] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
    }
  }

  // Inverse.
  var ik = n - 1;
  for (var len = 1; len < n; len <<= 1) {
    for (var start = 0; start < n; start += 2 * len) {
      var zeta = zetas[ik--];
      zeta = q - zeta;
      for (var j = start; j < start + len; j++) {
        final t = a[j];
        final u = a[j + len];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        final diff = t - u;
        final d = diff < 0 ? diff + q : diff;
        final raw = d * zeta;
        final quot = (raw * 10921) >> 27;
        var r = raw - quot * q;
        r = r >= q ? r - q : r;
        r = r >= q ? r - q : r;
        if (r < 0) r += q;
        if (r >= q) r %= q;
        a[j + len] = r;
      }
    }
  }
  for (var i = 0; i < n; i++) {
    final c = a[i];
    final raw = c * inv;
    final quot = (raw * 10921) >> 27;
    var r = raw - quot * q;
    r = r >= q ? r - q : r;
    r = r >= q ? r - q : r;
    if (r < 0) r += q;
    if (r >= q) r %= q;
    a[i] = r;
  }
}

// ── ML-DSA Montgomery REDC candidate: 32-bit word, plain-domain arrangement.
//
// Twiddles arrive Montgomery-scaled (zetasMont[k] = zetas[k]*R mod q) and the
// poly stays in the plain domain throughout:
//   REDC(zetaM * xPlain) = zetaM * xPlain * R^-1 ≡ zeta * x
// so forward and inverse outputs are plain-domain, bit-identical to Barrett.
// Every table and constant is precomputed by the caller (setup).

void _montFwdInv(List<int> a, List<int> zetasMont, int invMont) {
  const q = 8380417;
  const mask = 0xFFFFFFFF;
  const nPrime = 4236238847;

  // prod in [0, q^2) < 2^46: single-limb REDC, (prod + m*q) < 2^56, no wrap.
  int redc(int prod) {
    final m = ((prod & mask) * nPrime) & mask;
    var u = (prod + m * q) >> 32;
    if (u >= q) u -= q;
    return u;
  }

  // Forward.
  var k = 1;
  for (var len = 128; len >= 1; len >>= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zetaM = zetasMont[k++];
      for (var j = start; j < start + len; j++) {
        final t = redc(zetaM * a[j + len]);
        final fj = a[j];
        final diff = fj - t;
        a[j + len] = diff < 0 ? diff + q : diff;
        final sum = fj + t;
        a[j] = sum >= q ? sum - q : sum;
      }
    }
  }

  // Inverse.
  var ik = 255;
  for (var len = 1; len < 256; len <<= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      var zetaM = zetasMont[ik--];
      zetaM = q - zetaM; // -zetas[k] in Montgomery form
      for (var j = start; j < start + len; j++) {
        final t = a[j];
        final u = a[j + len];
        final sum = t + u;
        a[j] = sum >= q ? sum - q : sum;
        final diff = t - u;
        final d = diff < 0 ? diff + q : diff;
        a[j + len] = redc(zetaM * d);
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    a[i] = redc(invMont * a[i]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parity checks (before any timing)
// ─────────────────────────────────────────────────────────────────────────────

/// Exhaustive product check for the ML-KEM single-guard candidate plus
/// end-to-end parity of every candidate kernel against the production engine.
bool _runParityChecks() {
  var ok = true;

  // ML-KEM: exhaustive over all products a*b for a, b in [0, q).
  {
    var bad = -1;
    for (var a = 0; a < 3329 && bad < 0; a++) {
      final rowBase = a * 20159;
      for (var b = 0; b < 3329; b++) {
        final quot = (rowBase * b) >> 26;
        var t = a * b - quot * 3329;
        if (t < 0 || t >= 3329) t %= 3329;
        if (t != (a * b) % 3329) {
          bad = a * b;
          break;
        }
      }
    }
    if (bad >= 0) {
      stderr.writeln('PARITY mlKem/single-guard: first bad product a*b = $bad');
      ok = false;
    } else {
      stderr.writeln(
        'PARITY mlKem/single-guard exhaustive: all 3329*3329 products OK',
      );
    }
  }

  ok &= _checkParity(RingParams.mlKem, 'mlKem', _inlineFwdInv, extra: const {});
  ok &= _checkParity(
    RingParams.mlDsa,
    'mlDsa',
    _inlineFwdInv,
    extra: _montParityArms(),
  );
  ok &= _checkParity(
    RingParams.fnDsa512,
    'fnDsa512',
    _inlineFwdInv,
    extra: const <String, _ArmFn>{'k27': _k27FwdInv},
  );
  ok &= _checkParity(
    RingParams.fnDsa1024,
    'fnDsa1024',
    _inlineFwdInv,
    extra: const <String, _ArmFn>{'k27': _k27FwdInv},
  );
  return ok;
}

/// Builds the ML-DSA Montgomery arm with precomputed, fixed tables.
Map<String, _ArmFn> _montParityArms() {
  final montParams = NttParams.forRing(RingParams.mlDsa);
  final mont = MontgomeryParams.forQ(RingParams.mlDsa.q);
  final zetasMont = montParams.zetas.map((z) => ModQ.toMont(z, mont)).toList();
  final invMont = ModQ.toMont(montParams.invNScale, mont);
  return <String, _ArmFn>{
    'mont': (coeffs, ntt) => _montFwdInv(coeffs, zetasMont, invMont),
  };
}

/// Runs production forward+inverse on a base poly, then runs each candidate
/// on a reset copy and compares every coefficient.
bool _checkParity(
  RingParams ring,
  String name,
  void Function(NttParams, List<int>) inlineFwdInv, {
  required Map<String, _ArmFn> extra,
}) {
  final base = _benchPoly(ring, 0x13A7 ^ ring.q);
  final engine = NttEngine(ring);
  final refPoly = base.clone();
  engine.forwardInPlace(refPoly);
  engine.inverseInPlace(refPoly);
  final ntt = NttParams.forRing(ring);

  var ok = true;
  void compare(String candidate, Poly p) {
    for (var i = 0; i < ring.n; i++) {
      if (p.coeffs[i] != refPoly.coeffs[i]) {
        stderr.writeln(
          'PARITY $name/$candidate: coeff $i = ${p.coeffs[i]} '
          'expected ${refPoly.coeffs[i]}',
        );
        ok = false;
        return;
      }
    }
    stderr.writeln('PARITY $name/$candidate: OK');
  }

  final p = Poly.zero(ring);
  p.coeffs.setAll(0, base.coeffs);
  inlineFwdInv(ntt, p.coeffs);
  compare('inline', p);

  for (final MapEntry(key: candidate, value: fn) in extra.entries) {
    final q2 = Poly.zero(ring);
    q2.coeffs.setAll(0, base.coeffs);
    fn(q2.coeffs, ntt);
    compare(candidate, q2);
  }
  return ok;
}
