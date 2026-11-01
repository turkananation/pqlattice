/// Wrap-threshold boundary fixtures for the ML-DSA reduction work.
///
/// These are pure-math canaries: they pin, as executable evidence, the exact
/// product boundary where the legacy Barrett chain (k = 48, mu = 33587228)
/// overflows a 64-bit signed product — the boundary certified by the exact
/// integer audit as E16 — and the structural bounds of the 32-bit-word
/// Montgomery REDC arrangement (q^2 < 2^46). They do not import production
/// reduction code, so they stay valid before and after engine changes.
library;

import 'package:test/test.dart';

void main() {
  const q = 8380417;
  const legacyMu = 33587228;
  const legacyShift = 48;
  const maxInt63 = 0x7FFFFFFFFFFFFFFF; // 2^63 - 1

  group('legacy k=48 Barrett wrap edge (E16 boundary)', () {
    test('recorded boundary equals floor((2^63-1) / mu)', () {
      final edge = maxInt63 ~/ legacyMu;
      // The audit's exact value; a mismatch means the ledger record is wrong.
      expect(edge, 274609504447);
    });

    test('product just below the edge stays on the fast path', () {
      const p = 274609504447; // edge itself: edge * mu <= 2^63 - 1
      final product = p * legacyMu;
      expect(product >= 0, isTrue, reason: 'no int64 wrap at the edge');
      expect(product, lessThanOrEqualTo(maxInt63));
      // Legacy chain formula produces the correct residue without escape.
      final quot = product >> legacyShift;
      var r = p - quot * q;
      r = r >= q ? r - q : r;
      r = r >= q ? r - q : r;
      if (r < 0) r += q;
      expect(r, p % q);
    });

    test('product just above the edge wraps positive-and-negative', () {
      const p = 274609504448; // edge + 1
      final wrapped = p * legacyMu; // Dart int64 wrap
      // Mathematically p * mu > 2^63 - 1: the product must wrap. The VM wraps
      // modulo 2^64, so the signed value goes negative here (p*mu < 2^64).
      expect(
        wrapped < 0,
        isTrue,
        reason:
            'wrapped product is negative -> escape/hardware division '
            'would fire in the legacy chain (escape-hot, E16)',
      );
      // Overflow-free truth check: p exceeds floor((2^63-1)/mu), therefore
      // p * mu must exceed 2^63 - 1 by the flooring construction.
      expect(p, greaterThan(maxInt63 ~/ legacyMu));
    });

    test('butterfly-space products can and do exceed the edge', () {
      // zeta up to q-1 times a coefficient up to q-1 exceeds the edge:
      expect(
        (q - 1) * (q - 1),
        greaterThan(274609504447),
        reason: 'the k=48 chain is escape-hot on uniform butterfly products',
      );
    });
  });

  group('32-bit-word Montgomery REDC structural bounds', () {
    test('q^2 < 2^46 (single-limb REDC product bound)', () {
      expect(q * q, 70231389093889);
      expect(q * q, lessThan(1 << 46));
    });

    test('(q-1)^2 stays under the 2^46 bound', () {
      expect((q - 1) * (q - 1), 70231372333056);
      expect((q - 1) * (q - 1), lessThan(1 << 46));
    });

    test('REDC of canonical bound products gives canonical residues', () {
      const r = 1 << 32;
      const nPrime = 4236238847;

      int redc(int prod) {
        final m = ((prod & 0xFFFFFFFF) * nPrime) & 0xFFFFFFFF;
        var u = (prod + m * q) >> 32;
        if (u >= q) u -= q;
        return u;
      }

      expect(redc(0), 0);

      // (q-1)^2 * R^-1 mod q via an independent extended-Euclid inverse.
      final rInv = _invMod(r, q);
      final expectVal = (((q - 1) * (q - 1)) % q) * (rInv % q) % q;
      expect(redc((q - 1) * (q - 1)), expectVal);

      // REDC identity: REDC(x · R^2 mod q) = x · R mod q (the Montgomery form
      // of x). Montgomery multiplication keeps one R: REDC(toMont·toMont) is
      // the Montgomery form of x^2, canonical only after a second REDC. The
      // engine's butterflies pair one Mont-form operand with one plain
      // operand, so a single REDC returns canonical values (parity-proven).
      const r2 = 2365951;
      final rModQ = (1 << 32) % q;
      for (var x = 1; x < 16; x++) {
        final toMontX = redc((x * r2) % q);
        expect(toMontX, (x * rModQ) % q, reason: 'toMont via REDC, x=$x');
        expect(
          redc(toMontX * toMontX),
          (x * x * rModQ) % q,
          reason: 'Mont-form x^2, x=$x',
        );
        expect(
          redc(redc(toMontX * toMontX)),
          (x * x) % q,
          reason: 'canonical x^2 via double REDC, x=$x',
        );
      }
    });
  });
}

int _invMod(int a, int m) {
  var oldR = a % m, r = m;
  var oldS = 1, s = 0;
  while (r != 0) {
    final quot = oldR ~/ r;
    final tmpR = oldR - quot * r;
    oldR = r;
    r = tmpR;
    final tmpS = oldS - quot * s;
    oldS = s;
    s = tmpS;
  }
  return (oldS % m + m) % m;
}
