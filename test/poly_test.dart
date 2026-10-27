import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('Poly', () {
    final ring = RingParams.mlKem;

    test('zero has length n', () {
      final p = Poly.zero(ring);
      expect(p.n, 256);
      expect(p.coeffs.every((c) => c == 0), isTrue);
    });

    test('fromCoeffs rejects wrong length', () {
      expect(() => Poly.fromCoeffs(ring, <int>[1, 2, 3]), throwsArgumentError);
    });

    test('PolyOps.addInto', () {
      final a = Poly.fromCoeffs(ring, List<int>.filled(ring.n, 1));
      final b = Poly.fromCoeffs(ring, List<int>.filled(ring.n, 2));
      final c = Poly.zero(ring);
      PolyOps.addInto(c, a, b);
      expect(c.coeffs.every((x) => x == 3), isTrue);
    });
  });
}
