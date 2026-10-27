import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('PolyVec / PolyMat', () {
    final ring = RingParams.mlKem;

    test('PolyVec.zero length', () {
      final v = PolyVec.zero(ring, 3);
      expect(v.length, 3);
      expect(v[0].coeffs.every((c) => c == 0), isTrue);
    });

    test('PolyMat dimensions', () {
      final m = PolyMat.zero(ring, 2, 3);
      expect(m.rows, 2);
      expect(m.cols, 3);
      expect(m.at(1, 2).n, ring.n);
    });

    test('mulVecNttPlaceholder is unimplemented', () {
      final m = PolyMat.zero(ring, 2, 2);
      final v = PolyVec.zero(ring, 2);
      expect(() => m.mulVecNttPlaceholder(v), throwsUnimplementedError);
    });
  });
}
