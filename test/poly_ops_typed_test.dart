import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// Packed add/sub/neg/scale must match full `%` on coefficients in `[0, q)`.
void main() {
  final rings = <RingParams>[
    RingParams.mlKem,
    RingParams.mlDsa,
    RingParams.fnDsa512,
  ];

  for (final ring in rings) {
    test('${ring.name} packed add, sub, neg, scale match %', () {
      final rnd = Random(0x0E5 ^ ring.q);
      final av = List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q));
      final bv = List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q));
      final k = rnd.nextInt(ring.q);

      final packedA = Poly.fromCoeffs(ring, av);
      final packedB = Poly.fromCoeffs(ring, bv);
      final plainA = Poly.view(ring, List<int>.from(av));
      final plainB = Poly.view(ring, List<int>.from(bv));

      final addP = Poly.zero(ring);
      final addL = Poly.zero(ring);
      PolyOps.addInto(addP, packedA, packedB);
      PolyOps.addInto(addL, plainA, plainB);
      expect(addP.coeffs, addL.coeffs);

      final subP = Poly.zero(ring);
      final subL = Poly.zero(ring);
      PolyOps.subInto(subP, packedA, packedB);
      PolyOps.subInto(subL, plainA, plainB);
      expect(subP.coeffs, subL.coeffs);

      final negP = Poly.zero(ring);
      final negL = Poly.zero(ring);
      PolyOps.negInto(negP, packedA);
      PolyOps.negInto(negL, plainA);
      expect(negP.coeffs, negL.coeffs);

      final scaleP = Poly.zero(ring);
      final scaleL = Poly.zero(ring);
      PolyOps.scaleInto(scaleP, packedA, k);
      PolyOps.scaleInto(scaleL, plainA, k);
      expect(scaleP.coeffs, scaleL.coeffs);
    });
  }

  test('plain list add still fully reduces', () {
    final ring = RingParams.mlKem;
    final a = Poly.view(ring, List<int>.filled(ring.n, ring.q + 5));
    final b = Poly.view(ring, List<int>.filled(ring.n, 1));
    final dest = Poly.zero(ring);
    PolyOps.addInto(dest, a, b);
    expect(dest.coeffs.every((c) => c == 6), isTrue);
  });
}
