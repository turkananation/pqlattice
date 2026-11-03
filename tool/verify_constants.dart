#!/usr/bin/env dart

/// Offline verification of Barrett, Montgomery, and FN-DSA table constants.
///
/// Run from repository root:
///   dart run tool/verify_constants.dart
///
/// Pure SDK (dart:io + dart:math only): runs with or without `dart pub get`,
/// in CI (`test.yml`) and on any developer machine.
///
/// Replaces the former Python checker one-for-one: identical check list,
/// identical output lines, identical exit behavior (0 = all checks passed,
/// 1 = at least one failure). Two review notes for the adaptation:
///
/// - Barrett models are spot-checked over 3000 seeded products plus the same
///   fixed edge battery. The sampled products need not match the old Python
///   PRNG stream; the invariant is that every sampled product reduces
///   exactly like `%`.
/// - The two spots where the old script relied on Python bignums are written
///   to stay inside int64 here: `R² mod q` is computed as `(R mod q)² mod q`,
///   and the ML-DSA wrap-edge inequality is checked via the remainder
///   `wrapBound - wrapEdge·mu < mu` instead of the overflowing upper endpoint.
library;

import 'dart:io';
import 'dart:math' as math;

/// One reduce recipe under test: (q, scale, shift, label, model).
typedef BarrettModel = int Function(int prod, int q, int scale, int shift);

class _Recipe {
  const _Recipe(this.q, this.scale, this.shift, this.label, this.model);

  final int q;
  final int scale; // Barrett mu / ceil-quotient v
  final int shift;
  final String label;
  final BarrettModel model;
}

/// General Barrett recipe (any mu/shift): a 4-step correction window plus a
/// final `%` fallback.
int _barrett(int prod, int q, int mu, int shift) {
  var quot = (prod * mu) >> shift;
  var r = prod - quot * q;
  for (var i = 0; i < 4; i++) {
    if (r >= q) {
      r -= q;
    } else if (r < 0) {
      r += q;
    } else {
      break;
    }
  }
  if (r >= q) r %= q;
  return r;
}

/// pqcrypto-parity ceil-quotient single-guard chain (ML-KEM 20159/26).
///
/// Mirrors `NttEngine._mulBarrettMlKem`: one guard fires the `%` escape;
/// in-range products correct in a single conditional.
int _barrettCeilSingle(int prod, int q, int v, int shift) {
  var quot = (prod * v) >> shift;
  var r = prod - quot * q;
  if (r < 0 || r >= q) r %= q;
  return r;
}

/// FN-DSA k=27 chain (mu = 10921 = floor(2^27 / 12289)).
///
/// Mirrors `NttEngine.fnDsaReduceK27`: two positive-correction steps, a
/// negative fix, then the defensive escape guard.
int _barrettFnDsa(int prod, int q, int mu, int shift) {
  var quot = (prod * mu) >> shift;
  var r = prod - quot * q;
  if (r >= q) r -= q;
  if (r >= q) r -= q;
  if (r < 0) r += q;
  if (r >= q) r %= q;
  return r;
}

/// Extended Euclid, recursive: returns (g, x, y) with a·x + b·y = g.
(int, int, int) _egcd(int a, int b) {
  if (b == 0) return (a, 1, 0);
  final (g, x, y) = _egcd(b, a % b);
  return (g, y, x - (a ~/ b) * y);
}

int _invmod(int a, int m) {
  final (g, x, _) = _egcd(a % m, m);
  if (g != 1) throw StateError('not invertible');
  return x % m;
}

/// Generic Montgomery REDC over the int-word radix R = 2^logR.
///
/// Word-width note: `(a & rMask) * nPrime` can exceed 64 bits on the 32-bit
/// profile; the low bits survive because wrapping discards only high bits
/// and 2^32 divides 2^64, so the following `&` recovers the exact m.
/// `(a + t·q)` stays far below 2^64 for every profile produced here.
int _montReduce(int a, int q, int nPrime, int logR) {
  final rMask = (1 << logR) - 1;
  final t = ((a & rMask) * nPrime) & rMask;
  var u = (a + t * q) >> logR;
  if (u >= q) u -= q;
  if (u < 0) u += q;
  return u;
}

int _bitrev(int x, int bits) {
  var r = 0;
  for (var i = 0; i < bits; i++) {
    r = (r << 1) | (x & 1);
    x >>= 1;
  }
  return r;
}

/// a^e mod m; callers keep m at or below 12289, so every intermediate
/// square stays under 2^46 and int64 arithmetic is exact.
int _modPow(int b, int e, int m) {
  var result = 1;
  var base = b % m;
  while (e > 0) {
    if ((e & 1) == 1) result = (result * base) % m;
    base = (base * base) % m;
    e >>= 1;
  }
  return result;
}

/// Parses one `const List<int> <name> = [ ... ];` table out of the NTT
/// source text. The checker reads the shipped file rather than any public
/// export surface, mirroring the previous checker's file-text parse.
List<int>? _parseZetaTable(String text, String name) {
  final marker = '$name = [';
  final start = text.indexOf(marker);
  if (start < 0) return null;
  final end = text.indexOf('];', start);
  if (end < 0) return null;
  final body = text.substring(start + marker.length, end);
  final values = <int>[];
  var i = 0;
  while (i < body.length) {
    final c = body.codeUnitAt(i);
    if (c >= 0x30 && c <= 0x39) {
      var j = i + 1;
      while (j < body.length) {
        final d = body.codeUnitAt(j);
        if (d < 0x30 || d > 0x39) break;
        j++;
      }
      values.add(int.parse(body.substring(i, j)));
      i = j;
    } else {
      i++;
    }
  }
  return values;
}

/// Repository root: the parent of the tool/ directory containing this
/// script — the same contract the previous checker used.
String _repoRoot() {
  final scriptPath = File.fromUri(Platform.script).resolveSymbolicLinksSync();
  return File(scriptPath).parent.parent.path;
}

void main() {
  var errors = 0;

  // Barrett recipes: general model, ML-KEM ceil single-guard, FN-DSA k=27.
  const recipes = [
    _Recipe(3329, 5039, 24, 'barrett', _barrett),
    _Recipe(12289, 1365, 24, 'barrett', _barrett),
    _Recipe(8380417, 33587228, 48, 'barrett', _barrett),
    _Recipe(3329, 20159, 26, 'barrett_ceil_single', _barrettCeilSingle),
    _Recipe(12289, 10921, 27, 'barrett_fn_dsa', _barrettFnDsa),
  ];
  for (final recipe in recipes) {
    final rnd = math.Random(recipe.q);
    var bad = 0;
    for (var i = 0; i < 3000; i++) {
      final prod = rnd.nextInt(recipe.q) * rnd.nextInt(recipe.q);
      if (recipe.model(prod, recipe.q, recipe.scale, recipe.shift) !=
          prod % recipe.q) {
        bad++;
      }
    }
    final edgeProducts = <int>[
      0,
      1,
      recipe.q - 1,
      ((recipe.q - 1) * (recipe.q - 1)) ~/ 2,
      (recipe.q - 1) * (recipe.q - 1),
    ];
    for (final prod in edgeProducts) {
      if (recipe.model(prod, recipe.q, recipe.scale, recipe.shift) !=
          prod % recipe.q) {
        bad++;
      }
    }
    if (bad != 0) {
      stdout.writeln(
        'FAIL Barrett q=${recipe.q} v=${recipe.scale}/sh=${recipe.shift} '
        'bad=$bad',
      );
      errors++;
    } else {
      stdout.writeln(
        'OK   Barrett q=${recipe.q} v=${recipe.scale}/sh=${recipe.shift} '
        '(${recipe.label})',
      );
    }
  }

  // Provenance for the shipped engine chains: ML-KEM v = 20159 =
  // ceil(2^26 / 3329); FN-DSA mu = 10921 = floor(2^27 / 12289).
  if (20159 != ((1 << 26) + 3329 - 1) ~/ 3329) {
    stdout.writeln('FAIL ML-KEM v=20159 ceil constant');
    errors++;
  }
  if (10921 != (1 << 27) ~/ 12289) {
    stdout.writeln('FAIL FN-DSA mu=10921 floor constant');
    errors++;
  }
  if (errors == 0) {
    stdout.writeln('OK   engine chain provenance (mlKem ceil, fnDsa floor)');
  }

  // ML-DSA legacy k=48 wrap edge (E16): the boundary where the legacy int64
  // chain produces a wrapped (raw * mu) term. The generic/basemul path
  // still uses this recipe; the NTT engine's hot path is the monomorphic
  // 32-bit REDC chain instead.
  const wrapMu = 33587228;
  const wrapBound = 9223372036854775807; // 2^63 - 1
  final wrapEdge = wrapBound ~/ wrapMu;
  if (wrapEdge != 274609504447) {
    stdout.writeln('FAIL ML-DSA k=48 wrap edge $wrapEdge');
    errors++;
  } else if (wrapEdge * wrapMu > wrapBound ||
      wrapBound - wrapEdge * wrapMu >= wrapMu) {
    // wrap_bound ∈ [edge·mu, (edge+1)·mu), tested without evaluating the
    // overflowing upper endpoint directly.
    stdout.writeln('FAIL ML-DSA k=48 wrap edge inequality');
    errors++;
  } else {
    stdout.writeln('OK   ML-DSA k=48 wrap edge $wrapEdge');
  }

  // Montgomery parameter profiles: (q, nPrime, R² mod q, logR).
  const montTable = <(int, int, int, int)>[
    (3329, 3327, 1353, 16),
    (12289, 12287, 10952, 16),
    (8380417, 4236238847, 2365951, 32),
  ];
  for (final (q, nPrime, r2, logR) in montTable) {
    final radix = 1 << logR;
    final expectNp = (-_invmod(q, radix)) % radix;
    // R² mod q via (R mod q)²: the direct square R² exceeds int64 for
    // R = 2^32, and congruence mod q wipes the difference.
    final expectR2 = ((radix % q) * (radix % q)) % q;
    if (nPrime != expectNp || r2 != expectR2) {
      stdout.writeln('FAIL Mont constants q=$q');
      errors++;
      continue;
    }
    var bad = 0;
    for (var a = 0; a < q; a += math.max(1, q ~/ 80)) {
      final am = _montReduce((a % q) * r2, q, nPrime, logR);
      if (_montReduce(am, q, nPrime, logR) != a % q) {
        bad++;
      }
    }
    if (bad != 0) {
      stdout.writeln('FAIL Mont roundtrip q=$q bad=$bad');
      errors++;
    } else {
      stdout.writeln('OK   Mont q=$q');
    }
  }

  // FN-DSA zetas: regenerate every twiddle from the cited primitive roots
  // and compare all of them against the shipped tables.
  const tablePath = '/lib/src/ntt/fndsa_tables.dart';
  List<int>? z512;
  List<int>? z1024;
  try {
    final text = File('${_repoRoot()}$tablePath').readAsStringSync();
    z512 = _parseZetaTable(text, 'fnDsa512Zetas');
    z1024 = _parseZetaTable(text, 'fnDsa1024Zetas');
  } on FileSystemException {
    // Parse-failure branch below reports it.
  }
  if (z512 == null || z1024 == null) {
    stdout.writeln('FAIL could not parse fndsa_tables.dart');
    exit(1);
  }
  const qFn = 12289;
  var ok512 = z512.length == 512;
  for (var k = 0; k < 512 && ok512; k++) {
    if (z512[k] != _modPow(49, _bitrev(k, 9), qFn)) ok512 = false;
  }
  if (!ok512) {
    stdout.writeln('FAIL FN-DSA-512 zetas');
    errors++;
  } else {
    stdout.writeln('OK   FN-DSA-512 zetas');
  }
  var ok1024 = z1024.length == 1024;
  for (var k = 0; k < 1024 && ok1024; k++) {
    if (z1024[k] != _modPow(7, _bitrev(k, 10), qFn)) ok1024 = false;
  }
  if (!ok1024) {
    stdout.writeln('FAIL FN-DSA-1024 zetas');
    errors++;
  } else {
    stdout.writeln('OK   FN-DSA-1024 zetas');
  }

  if (errors > 0) {
    stdout.writeln('$errors failure(s)');
    exit(1);
  }
  stdout.writeln('all constant checks passed');
}
