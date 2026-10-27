import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  final ring = RingParams.mlDsa;
  final ntt = NttEngine(ring, params: NttParams.mlDsa());

  test('ML-DSA zetas loaded', () {
    expect(NttParams.mlDsa().zetas.length, 256);
    expect(NttParams.mlDsa().invNScale, 8347681);
  });

  test('ML-DSA NTT round-trip', () {
    final rnd = Random(3);
    final coeffs = List<int>.generate(256, (_) => rnd.nextInt(8380417));
    final a = Poly.fromCoeffs(ring, coeffs);
    final back = ntt.inverse(ntt.forward(a));
    for (var i = 0; i < 256; i++) {
      expect(back.coeffs[i] % 8380417, a.coeffs[i] % 8380417, reason: 'i=$i');
    }
  });

  test('in-place NTT matches allocating API', () {
    final a = Poly.fromCoeffs(
      ring,
      List<int>.generate(256, (i) => (i * 12345) % 8380417),
    );
    final b = a.clone();
    final out = ntt.forward(a);
    ntt.forwardInPlace(b);
    expect(b.coeffs, out.coeffs);
  });

  group('ML-DSA NTT × pointwise basemul vs schoolbook (L3)', () {
    test('random polys agree with schoolbook negacyclic', () {
      final rnd = Random(0x1753);
      randPoly() => List<int>.generate(256, (_) => rnd.nextInt(8380417));
      final a = Poly.fromCoeffs(ring, randPoly());
      final b = Poly.fromCoeffs(ring, randPoly());

      final school = RingMul.schoolbookNegacyclic(a, b, ring);
      final cHat = Basemul.pointwise(ntt.forward(a), ntt.forward(b), ring);
      final c = ntt.inverse(cHat);

      for (var i = 0; i < 256; i++) {
        expect(c.coeffs[i], school.coeffs[i], reason: 'coeff $i');
      }
    });

    test('boundary polys agree with schoolbook', () {
      final cases = <List<int>>[
        List<int>.filled(256, 0), // zero
        List<int>.filled(256, 1), // all ones
        List<int>.generate(256, (i) => (i * 1) % 8380417),
        List<int>.generate(256, (i) => (8380417 - 1 - i) % 8380417),
      ];
      for (final vals in cases) {
        final a = Poly.fromCoeffs(ring, vals);
        final b = Poly.fromCoeffs(ring, vals.reversed.toList());
        final school = RingMul.schoolbookNegacyclic(a, b, ring);
        final cHat = Basemul.pointwise(ntt.forward(a), ntt.forward(b), ring);
        final c = ntt.inverse(cHat);
        for (var i = 0; i < 256; i++) {
          expect(c.coeffs[i], school.coeffs[i], reason: 'boundary coeff $i');
        }
      }
    });
  });
}
