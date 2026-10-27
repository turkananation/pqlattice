import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  for (final q in [3329, 12289, 8380417]) {
    test('Barrett q=$q matches % on random products', () {
      final p = BarrettParams.forQ(q);
      expect(p.isReady, isTrue);
      final rnd = Random(q);
      for (var i = 0; i < 2500; i++) {
        final x = rnd.nextInt(q);
        final y = rnd.nextInt(q);
        final prod = x * y;
        expect(
          ModQ.reduceBarrett(prod, p),
          ModQ.reduce(prod, q),
          reason: 'prod=$prod',
        );
      }
    });

    test('Barrett q=$q matches % on edge products', () {
      final p = BarrettParams.forQ(q);
      final edges = <int>[0, 1, q - 1, q, q + 1, q * q - 1, (q - 1) * (q - 1)];
      for (final a in edges) {
        if (a < 0) continue;
        expect(ModQ.reduceBarrett(a, p), ModQ.reduce(a, q), reason: 'a=$a');
      }
    });
  }

  test('ML-DSA Barrett uses shift wide enough for q^2', () {
    final p = BarrettParams.mlDsa;
    expect(p.shift, greaterThanOrEqualTo(46));
    expect(p.mu, isNonZero);
  });
}
