import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('ModQ', () {
    const q = 3329;

    test('reduce maps into [0, q)', () {
      expect(ModQ.reduce(0, q), 0);
      expect(ModQ.reduce(q - 1, q), q - 1);
      expect(ModQ.reduce(q, q), 0);
      expect(ModQ.reduce(q + 5, q), 5);
      expect(ModQ.reduce(-1, q), q - 1);
      expect(ModQ.reduce(-q, q), 0);
    });

    test('add/sub/mul stay in range', () {
      expect(ModQ.add(q - 1, 2, q), 1);
      expect(ModQ.sub(1, 2, q), q - 1);
      expect(ModQ.mul(3, 5, q), 15);
    });

    test('rejects non-positive modulus', () {
      expect(() => ModQ.reduce(1, 0), throwsArgumentError);
    });
  });
}
