import 'dart:math';

import 'package:pqlattice/pqlattice.dart';
import 'package:test/test.dart';

void main() {
  group('NttEngine construction', () {
    test('selects tables from ring without explicit NttParams', () {
      final e = NttEngine(RingParams.mlKem);
      expect(e.params.hasZetas, isTrue);
      expect(e.params.zetas.length, 128);
    });

    test('rejects mismatched NttParams', () {
      expect(
        () => NttEngine(RingParams.mlKem, params: NttParams.mlDsa()),
        throwsArgumentError,
      );
    });

    test('rejects unknown ring for NttParams.forRing', () {
      final toy = RingParams(q: 17, n: 8, name: 'toy');
      expect(() => NttParams.forRing(toy), throwsArgumentError);
    });
  });

  group('NTT round-trip (all shipped profiles)', () {
    final cases = <(RingParams, int Function(Random))>[
      (RingParams.mlKem, (r) => r.nextInt(3329)),
      (RingParams.mlDsa, (r) => r.nextInt(8380417)),
      (RingParams.fnDsa512, (r) => r.nextInt(12289)),
      (RingParams.fnDsa1024, (r) => r.nextInt(12289)),
    ];

    for (final c in cases) {
      final ring = c.$1;
      final sample = c.$2;
      test('${ring.name} inverse(forward(a)) == a', () {
        final engine = NttEngine(ring);
        final rnd = Random(ring.n ^ ring.q);
        final coeffs = List<int>.generate(ring.n, (_) => sample(rnd));
        final a = Poly.fromCoeffs(ring, coeffs);
        final back = engine.inverse(engine.forward(a));
        for (var i = 0; i < ring.n; i++) {
          expect(back.coeffs[i], a.coeffs[i], reason: 'coeff $i');
        }
      });
    }
  });

  test('mismatched poly ring throws', () {
    final engine = NttEngine(RingParams.mlKem);
    final other = RingParams(q: 17, n: 8, name: 'toy');
    expect(() => engine.forward(Poly.zero(other)), throwsArgumentError);
  });

  group('forwardVec / inverseVec (all profiles)', () {
    final cases = <(RingParams, int Function(Random))>[
      (RingParams.mlKem, (r) => r.nextInt(3329)),
      (RingParams.mlDsa, (r) => r.nextInt(8380417)),
      (RingParams.fnDsa512, (r) => r.nextInt(12289)),
      (RingParams.fnDsa1024, (r) => r.nextInt(12289)),
    ];

    for (final c in cases) {
      final ring = c.$1;
      final sample = c.$2;
      test('${ring.name} forwardVec/inverseVec round-trip', () {
        final engine = NttEngine(ring);
        final rnd = Random(0xCAFE ^ ring.q);
        final polys = List<Poly>.generate(4, (_) {
          return Poly.fromCoeffs(
            ring,
            List<int>.generate(ring.n, (_) => sample(rnd)),
          );
        });
        final vec = PolyVec.fromPolys(ring, polys);
        final back = engine.inverseVec(engine.forwardVec(vec));
        for (var i = 0; i < vec.length; i++) {
          for (var j = 0; j < ring.n; j++) {
            expect(
              back[i].coeffs[j] % ring.q,
              vec[i].coeffs[j] % ring.q,
              reason: '${ring.name} poly $i coeff $j',
            );
          }
        }
      });

      test('${ring.name} forwardVec rejects wrong ring', () {
        final engine = NttEngine(ring);
        final other = RingParams(q: 17, n: 8, name: 'toy');
        final bad = PolyVec.fromPolys(
          other,
          List.generate(2, (_) => Poly.zero(other)),
        );
        expect(() => engine.forwardVec(bad), throwsArgumentError);
      });
    }
  });
}
