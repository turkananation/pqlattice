import 'dart:typed_data';

import '../mod/mod_q.dart';
import '../mod/montgomery_params.dart';
import 'ntt_reduce.dart';

/// Montgomery-domain NTT butterflies on staged `Int32List` lanes.
///
/// The engine copies the polynomial into its scratch workspace, converts the
/// domain there, runs one of these kernels, and copies back. Twiddles and the
/// inverse scale are Montgomery form, computed once when the engine is built.
/// Products use [montMulR16] or [mlDsaRedc]. Coefficients stay in `[0, q)`.
///
/// This path is opt-in. The default engine does not call it.
void montToDomain(Int32List f, MontgomeryParams mont) {
  for (var i = 0; i < f.length; i++) {
    f[i] = ModQ.toMont(f[i], mont);
  }
}

void montFromDomain(Int32List f, MontgomeryParams mont) {
  for (var i = 0; i < f.length; i++) {
    f[i] = ModQ.fromMont(f[i], mont);
  }
}

/// ML-KEM forward, `q = 3329`, `n = 256`. Incomplete NTT, stops at `len = 2`.
void mlKemMontForward(Int32List f, List<int> zetasMont) {
  const q = 3329;
  const nPrime = 3327;
  var k = 1;
  for (var len = 128; len >= 2; len >>= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = zetasMont[k++];
      for (var j = start; j < start + len; j++) {
        final t = montMulR16(zeta, f[j + len], q, nPrime);
        final lo = f[j];
        f[j + len] = _subq(lo, t, q);
        f[j] = _addq(lo, t, q);
      }
    }
  }
}

/// ML-KEM inverse. [invMont] is `n^{-1}` already in Montgomery form.
void mlKemMontInverse(Int32List f, List<int> zetasMont, int invMont) {
  const q = 3329;
  const nPrime = 3327;
  var k = 127;
  for (var len = 2; len <= 128; len <<= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = zetasMont[k--];
      for (var j = start; j < start + len; j++) {
        final t = f[j];
        final u = f[j + len];
        f[j] = _addq(t, u, q);
        f[j + len] = montMulR16(zeta, _subq(u, t, q), q, nPrime);
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    f[i] = montMulR16(f[i], invMont, q, nPrime);
  }
}

/// ML-DSA forward, `q = 8380417`, `n = 256`. Complete NTT.
void mlDsaMontForward(Int32List f, List<int> zetasMont) {
  const q = 8380417;
  var k = 1;
  for (var len = 128; len >= 1; len >>= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = zetasMont[k++];
      for (var j = start; j < start + len; j++) {
        final t = mlDsaRedc(zeta * f[j + len]);
        final lo = f[j];
        f[j + len] = _subq(lo, t, q);
        f[j] = _addq(lo, t, q);
      }
    }
  }
}

/// ML-DSA inverse. Conjugate twiddle is `q - zeta` in Montgomery form.
void mlDsaMontInverse(Int32List f, List<int> zetasMont, int invMont) {
  const q = 8380417;
  var k = 255;
  for (var len = 1; len < 256; len <<= 1) {
    for (var start = 0; start < 256; start += 2 * len) {
      final zeta = q - zetasMont[k--];
      for (var j = start; j < start + len; j++) {
        final t = f[j];
        final u = f[j + len];
        f[j] = _addq(t, u, q);
        f[j + len] = mlDsaRedc(_subq(t, u, q) * zeta);
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    f[i] = mlDsaRedc(f[i] * invMont);
  }
}

/// FN-DSA forward, `q = 12289`, `n` is 512 or 1024.
void fnDsaMontForward(Int32List f, List<int> zetasMont) {
  const q = 12289;
  const nPrime = 12287;
  final n = f.length;
  var k = 1;
  for (var len = n >> 1; len >= 1; len >>= 1) {
    for (var start = 0; start < n; start += 2 * len) {
      final zeta = zetasMont[k++];
      for (var j = start; j < start + len; j++) {
        final t = montMulR16(zeta, f[j + len], q, nPrime);
        final lo = f[j];
        f[j + len] = _subq(lo, t, q);
        f[j] = _addq(lo, t, q);
      }
    }
  }
}

/// FN-DSA inverse. Conjugate twiddle is `q - zeta` in Montgomery form.
void fnDsaMontInverse(Int32List f, List<int> zetasMont, int invMont) {
  const q = 12289;
  const nPrime = 12287;
  final n = f.length;
  var k = n - 1;
  for (var len = 1; len < n; len <<= 1) {
    for (var start = 0; start < n; start += 2 * len) {
      final zeta = q - zetasMont[k--];
      for (var j = start; j < start + len; j++) {
        final t = f[j];
        final u = f[j + len];
        f[j] = _addq(t, u, q);
        f[j + len] = montMulR16(_subq(t, u, q), zeta, q, nPrime);
      }
    }
  }
  for (var i = 0; i < n; i++) {
    f[i] = montMulR16(f[i], invMont, q, nPrime);
  }
}

int _addq(int a, int b, int q) {
  final sum = a + b;
  final sn = sum - q;
  return sum - (q & ~(sn >> 63));
}

int _subq(int a, int b, int q) {
  final d = a - b;
  return d + (q & (d >> 63));
}
