import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// Packed-lane basemul must match the plain-[List] recipe, and one engine
/// must be able to transform two polynomials in a row on its reused scratch.
void main() {
  final rings = <RingParams>[
    RingParams.mlKem,
    RingParams.mlDsa,
    RingParams.fnDsa512,
    RingParams.fnDsa1024,
  ];

  for (final ring in rings) {
    test('${ring.name} packed pointwise matches a plain list', () {
      final rnd = Random(0xB45E ^ ring.q ^ ring.n);
      final a = List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q));
      final b = List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q));
      final packed = Basemul.pointwise(
        Poly.fromCoeffs(ring, a),
        Poly.fromCoeffs(ring, b),
        ring,
      );
      final plain = Basemul.pointwise(
        Poly.view(ring, List<int>.from(a)),
        Poly.view(ring, List<int>.from(b)),
        ring,
      );
      expect(packed.coeffs, plain.coeffs);
    });

    test('${ring.name} reused scratch matches a fresh engine', () {
      final rnd = Random(0x5C4A ^ ring.q ^ ring.n);
      final a = Poly.fromCoeffs(
        ring,
        List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
      );
      final b = Poly.fromCoeffs(
        ring,
        List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
      );
      final reused = NttEngine(ring);
      final forwardA = reused.forward(a);
      final forwardB = reused.forward(b);
      expect(forwardA.coeffs, NttEngine(ring).forward(a).coeffs);
      expect(forwardB.coeffs, NttEngine(ring).forward(b).coeffs);
      expect(reused.inverse(forwardA).coeffs, a.coeffs);
      expect(reused.inverse(forwardB).coeffs, b.coeffs);
    });
  }

  test('ML-KEM pairs on packed lanes match a plain list', () {
    const ring = RingParams.mlKem;
    final rnd = Random(0xA11);
    final a = List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q));
    final b = List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q));
    final packed = Basemul.mlKemPairs(
      Poly.fromCoeffs(ring, a),
      Poly.fromCoeffs(ring, b),
      ring,
    );
    final plain = Basemul.mlKemPairs(
      Poly.view(ring, List<int>.from(a)),
      Poly.view(ring, List<int>.from(b)),
      ring,
    );
    expect(packed.coeffs, plain.coeffs);
  });
}
