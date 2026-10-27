import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  final ring = RingParams.mlKem;
  final ntt = NttEngine(ring, params: NttParams.mlKem());

  test('ML-KEM zetas loaded from pqcrypto port', () {
    final p = NttParams.mlKem();
    expect(p.zetas.length, 128);
    expect(p.gammas.length, 128);
    expect(p.zetas.first, 1);
    expect(p.invNScale, 3303);
  });

  test('NTT round-trip random poly', () {
    final rnd = Random(7);
    final coeffs = List<int>.generate(256, (_) => rnd.nextInt(3329));
    final a = Poly.fromCoeffs(ring, coeffs);
    final back = ntt.inverse(ntt.forward(a));
    for (var i = 0; i < 256; i++) {
      expect(back.coeffs[i], a.coeffs[i], reason: 'coeff $i');
    }
  });

  test('NTT mul agrees with schoolbook', () {
    final rnd = Random(99);
    List<int> randPoly() => List<int>.generate(256, (_) => rnd.nextInt(3329));
    final a = Poly.fromCoeffs(ring, randPoly());
    final b = Poly.fromCoeffs(ring, randPoly());
    final school = RingMul.schoolbookNegacyclic(a, b, ring);
    final cHat = Basemul.mlKemPairs(ntt.forward(a), ntt.forward(b), ring);
    final c = ntt.inverse(cHat);
    for (var i = 0; i < 256; i++) {
      expect(c.coeffs[i], school.coeffs[i], reason: 'coeff $i');
    }
  });
}
