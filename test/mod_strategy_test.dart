import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('reduction strategy', () {
    test('BarrettParams.forQ(3329) is ready', () {
      final b = BarrettParams.forQ(3329);
      expect(b.isReady, isTrue);
      expect(ModQ.reduceBarrett(100, b), ModQ.reduce(100, 3329));
    });

    test('MontgomeryParams.forQ(3329) is ready', () {
      final m = MontgomeryParams.forQ(3329);
      expect(m.isReady, isTrue);
      expect(m.logR, 16);
      expect(ModQ.toMont(5, m), ModQ.toMont(5, m));
      expect(ModQ.fromMont(ModQ.toMont(5, m), m), 5);
    });

    test('Montgomery fail-closed for unknown modulus', () {
      final m = MontgomeryParams.forQ(17);
      expect(m.isReady, isFalse);
      expect(() => ModQ.montMul(1, 1, m), throwsStateError);
    });

    test('csubq and freeze', () {
      const q = 3329;
      expect(ModQ.csubq(q + 3, q), 3);
      expect(ModQ.csubq(3, q), 3);
      expect(ModQ.freeze(-1, q), q - 1);
    });
  });
}
