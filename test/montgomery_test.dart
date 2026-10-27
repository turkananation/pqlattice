import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('Montgomery domain identities', () {
    for (final entry in [
      (3329, MontgomeryParams.mlKem),
      (12289, MontgomeryParams.fnDsa),
      (8380417, MontgomeryParams.mlDsa),
    ]) {
      final q = entry.$1;
      final params = entry.$2;

      test('q=$q ready and toMont/fromMont round-trip', () {
        expect(params.isReady, isTrue);
        expect(params.q, q);
        final rnd = Random(q);
        for (var i = 0; i < 400; i++) {
          final a = rnd.nextInt(q);
          final am = ModQ.toMont(a, params);
          expect(ModQ.fromMont(am, params), a);
        }
      });

      test('q=$q montMul matches plain product', () {
        final rnd = Random(q ^ 0x9e3779b9);
        for (var i = 0; i < 400; i++) {
          final a = rnd.nextInt(q);
          final b = rnd.nextInt(q);
          final am = ModQ.toMont(a, params);
          final bm = ModQ.toMont(b, params);
          final pm = ModQ.montMul(am, bm, params);
          expect(ModQ.fromMont(pm, params), (a * b) % q);
        }
      });
    }

    test('unready params throw on montReduce', () {
      const bad = MontgomeryParams(q: 17, nPrime: 0, r2: 0, logR: 0);
      expect(() => ModQ.montReduce(1, bad), throwsStateError);
    });
  });
}
