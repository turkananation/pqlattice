import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('RingMul.schoolbookNegacyclic', () {
    // Tiny ring for exhaustive-style checks (not ML-KEM size).
    const ring = RingParams(q: 17, n: 4, name: 'toy');

    test('e0 * e0 = e0', () {
      final a = Poly.fromCoeffs(ring, <int>[1, 0, 0, 0]);
      final c = RingMul.schoolbookNegacyclic(a, a, ring);
      expect(c.coeffs, <int>[1, 0, 0, 0]);
    });

    test('x * x = x^2', () {
      final x = Poly.fromCoeffs(ring, <int>[0, 1, 0, 0]);
      final c = RingMul.schoolbookNegacyclic(x, x, ring);
      expect(c.coeffs, <int>[0, 0, 1, 0]);
    });

    test('x^2 * x^2 = -1 (negacyclic)', () {
      final x2 = Poly.fromCoeffs(ring, <int>[0, 0, 1, 0]);
      final c = RingMul.schoolbookNegacyclic(x2, x2, ring);
      // x^4 ≡ -1 ⇒ coeff 0 is q-1
      expect(c.coeffs[0], ring.q - 1);
      expect(c.coeffs.sublist(1), <int>[0, 0, 0]);
    });
  });
}
