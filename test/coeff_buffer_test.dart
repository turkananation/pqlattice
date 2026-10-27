import 'dart:typed_data';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('CoeffLayout', () {
    test('ML-KEM and FN-DSA use i16', () {
      expect(CoeffLayout.widthFor(RingParams.mlKem), CoeffWidth.i16);
      expect(CoeffLayout.widthFor(RingParams.fnDsa512), CoeffWidth.i16);
      expect(CoeffLayout.widthFor(RingParams.fnDsa1024), CoeffWidth.i16);
    });

    test('ML-DSA uses i32', () {
      expect(CoeffLayout.widthFor(RingParams.mlDsa), CoeffWidth.i32);
    });

    test('i8 does not fit ML-KEM q', () {
      expect(CoeffLayout.fitsReduced(RingParams.mlKem, CoeffWidth.i8), isFalse);
      expect(CoeffLayout.fitsReduced(RingParams.mlKem, CoeffWidth.i16), isTrue);
    });
  });

  group('Poly packed storage', () {
    test('zero is Int16List for ML-KEM', () {
      final p = Poly.zero(RingParams.mlKem);
      expect(p.coeffs, isA<Int16List>());
      expect(p.isPacked, isTrue);
      expect(p.width, CoeffWidth.i16);
    });

    test('zero is Int32List for ML-DSA', () {
      final p = Poly.zero(RingParams.mlDsa);
      expect(p.coeffs, isA<Int32List>());
      expect(p.width, CoeffWidth.i32);
    });

    test('fromCoeffs preserves values', () {
      final ring = RingParams.mlKem;
      final p = Poly.fromCoeffs(ring, List<int>.generate(256, (i) => i % 3329));
      expect(p.coeffs[10], 10);
      expect(p.coeffs, isA<Int16List>());
    });
  });
}
