import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('BarrettParams ML-KEM (FIPS 203 q=3329)', () {
    final params = BarrettParams.mlKem;

    test('isReady with standard constants', () {
      expect(params.isReady, isTrue);
      expect(params.q, 3329);
      expect(params.mu, 5039);
      expect(params.shift, 24);
    });

    test('reduceBarrett matches reduce on random products', () {
      final rnd = Random(0xC0FFEE);
      for (var i = 0; i < 2000; i++) {
        final x = rnd.nextInt(3329);
        final y = rnd.nextInt(3329);
        final prod = x * y;
        expect(
          ModQ.reduceBarrett(prod, params),
          ModQ.reduce(prod, 3329),
          reason: 'prod=$prod',
        );
      }
    });

    test('reduceBarrett matches reduce on range [0, q^2]', () {
      final rnd = Random(42);
      for (var i = 0; i < 1000; i++) {
        final a = rnd.nextInt(3329 * 3329 + 1);
        expect(ModQ.reduceBarrett(a, params), ModQ.reduce(a, 3329));
      }
    });

    test('mulBarrett matches mul', () {
      expect(ModQ.mulBarrett(1234, 2345, params), ModQ.mul(1234, 2345, 3329));
    });
  });

  test('BarrettParams.forQ other moduli ready with documented constants', () {
    final fnDsa = BarrettParams.forQ(12289);
    expect(fnDsa.isReady, isTrue);
    expect(fnDsa.mu, 1365);
    expect(fnDsa.shift, 24);
    expect(fnDsa.maxInputAbs, 12289 * 12289);

    final mlDsa = BarrettParams.forQ(8380417);
    expect(mlDsa.isReady, isTrue);
    expect(mlDsa.mu, 33587228);
    expect(mlDsa.shift, 48);
    expect(mlDsa.maxInputAbs, 8380417 * 8380417);
  });

  test('BarrettParams.forQ unknown modulus not ready', () {
    expect(BarrettParams.forQ(17).isReady, isFalse);
  });
}
