import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

/// [NttEngine.basemul] stays in the engine's domain and matches schoolbook
/// after inverse, for both the default engine and the Montgomery engine.
void main() {
  final rings = <RingParams>[
    RingParams.mlKem,
    RingParams.mlDsa,
    RingParams.fnDsa512,
  ];

  for (final ring in rings) {
    test('${ring.name} plain engine basemul matches schoolbook', () {
      _expectSchoolbook(NttEngine(ring), ring);
    });

    test('${ring.name} montgomery engine basemul matches schoolbook', () {
      final mont = MontgomeryParams.forQ(ring.q);
      _expectSchoolbook(NttEngine(ring, montgomeryParams: mont), ring);
    });
  }

  test('montgomery engine exposes the params it was built with', () {
    final mont = MontgomeryParams.mlKem;
    final engine = NttEngine(RingParams.mlKem, montgomeryParams: mont);
    expect(engine.montgomeryParams, same(mont));
    expect(NttEngine(RingParams.mlKem).montgomeryParams, isNull);
  });
}

void _expectSchoolbook(NttEngine engine, RingParams ring) {
  final rnd = Random(0xBACE ^ ring.q ^ ring.n);
  final a = Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
  final b = Poly.fromCoeffs(
    ring,
    List<int>.generate(ring.n, (_) => rnd.nextInt(ring.q)),
  );
  final school = RingMul.schoolbookNegacyclic(a, b, ring);
  final product = engine.inverse(
    engine.basemul(engine.forward(a), engine.forward(b)),
  );
  expect(product.coeffs, school.coeffs);
}
